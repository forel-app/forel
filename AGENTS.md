# Forel — AI & Agent Guidelines

> **Source of truth for all AI coding agents** (Claude Code, Cursor, Copilot, etc.).
> `CLAUDE.md` is a symlink to this file — edit only `AGENTS.md`.

---

## What Forel is

Forel is an **open-source macOS file-automation app** (think Hazel). It watches folders and runs user-defined rules (conditions → actions) on new/changed files. It lives in the system tray and applies rules silently in the background.

**Status: alpha.** Core plumbing works; many planned features are not yet implemented.

---

## Stack

| Layer | Technology |
|---|---|
| App shell | Tauri 2 |
| Backend | Rust (stable) |
| Frontend | React 19 + TypeScript |
| State (UI) | Zustand 5 |
| Persistence | SQLite via `rusqlite` (bundled) |
| File watching | `notify` 6 (FSEvents on macOS) |
| macOS tags | `xattr` + `plist` crates |
| Icons | `lucide-react` |
| Build | Vite 7 + `pnpm` |

---

## The IPC boundary — the most important constraint

Tauri enforces a **hard process boundary** between the React frontend (WebView) and the Rust backend. They communicate exclusively through **typed IPC commands**.

```
React (WebView)                   Rust (native process)
──────────────────                ────────────────────────────────
invoke("command_name", args)  →   #[tauri::command] fn command_name(...)
        ↑                                   |
        └──────────── JSON response ────────┘
```

**Every frontend feature that reads or mutates app state requires a matching Rust command.**
There is no shared memory, no filesystem shortcut, no hidden channel.

When adding a feature, ask yourself: _"Does the frontend need data from the OS/DB, or does it need to trigger a side effect?"_ If yes → you need a Rust command.

### Adding a command — the full checklist

1. **`src-tauri/src/commands.rs`** — write the `#[tauri::command]` function.
   - Accept `state: State<AppState>` for DB/watcher access.
   - Accept `app: AppHandle` if you need to rebuild the tray afterward.
   - Return `Result<T, String>` — errors become JS `Promise` rejections.

2. **`src-tauri/src/lib.rs`** — register it in `invoke_handler!`:
   ```rust
   commands::your_new_command,
   ```
   A command not listed here is invisible to the frontend — no build error, it just silently fails.

3. **`src/store/index.ts`** — add a method to `useForelStore` that calls `invoke<ReturnType>("your_new_command", { arg })`.

4. **`src/types/index.ts`** — add or extend types if the command returns new shapes.

5. **`src-tauri/capabilities/default.json`** — if your command touches a Tauri plugin (fs, dialog, etc.), add the required permission here.

---

## Repository layout

```
forel/
├── src/                          React frontend
│   ├── App.tsx                   Root: layout, sidebar, rule list
│   ├── App.css                   All styles (single file, no CSS modules)
│   ├── main.tsx                  React entry point
│   ├── components/
│   │   ├── RuleEditor.tsx        Modal: edit conditions + actions for a rule
│   │   ├── RuleList.tsx          Right panel: list rules for selected folder
│   │   └── Sidebar.tsx           Left panel: watched folders
│   ├── store/
│   │   └── index.ts              Zustand store — all invoke() calls live here
│   └── types/
│       └── index.ts              Shared TS types + UI label maps
│
└── src-tauri/                    Rust backend (Tauri 2)
    ├── Cargo.toml
    ├── tauri.conf.json           App metadata, window config, bundle ID
    ├── capabilities/
    │   └── default.json          Tauri permission grants
    └── src/
        ├── lib.rs                App setup: DB init, watcher start, tray, IPC registration
        ├── main.rs               Binary entry (calls lib::run)
        ├── state.rs              AppState struct (db, watcher, paused flag)
        ├── commands.rs           All #[tauri::command] functions
        ├── db.rs                 SQLite schema + all query helpers
        ├── tray.rs               System tray icon, menu, event handler
        ├── watcher.rs            notify-based FSEvents loop
        └── rules/
            ├── mod.rs            Re-exports
            ├── model.rs          Rule/Condition/Action types (serde ↔ DB)
            ├── condition.rs      Condition evaluation logic
            ├── action.rs         Action execution logic (move, tag, script…)
            └── engine.rs         Applies rules to a file path
```

---

## Dev commands

```bash
# Run app in dev mode (hot-reload frontend, Rust recompiles on change)
pnpm tauri dev

# Type-check frontend only
pnpm build          # tsc + vite build

# Check Rust without linking (fast)
cargo check         # run from src-tauri/

# Full Rust build (slow, needed before tauri dev first run)
cargo build         # run from src-tauri/

# Regenerate all icon sizes from a square PNG source
pnpm tauri icon assets/forel-icon.png

# Package the app (.dmg / .app)
pnpm tauri build
```

> `pnpm` is required (`npm` and `yarn` are not used). Run all JS commands from the repo root.
> Run `cargo` commands from `src-tauri/`.

---

## Compilation warnings policy

**Every `cargo check` and `cargo build` run must finish with zero warnings introduced by your change.**

Run this before considering any Rust work done:

```bash
cargo check 2>&1 | grep "^warning"
```

If the output is non-empty, fix every warning before moving on.

### Common warnings and how to fix them

| Warning | Fix |
|---|---|
| `dead_code` — unused function or variant | Remove it. Do not add `#[allow(dead_code)]`. |
| `unused_variable` | Remove it, or prefix with `_` if intentionally unused. |
| `unused_import` | Remove the `use` line. |
| `unused_must_use` — `Result` ignored | Handle with `?`, `.ok()`, or `let _ =` with a comment explaining why. |
| `deprecated` | Use the replacement API shown in the warning. |
| `non_snake_case` / `non_camel_case_types` | Rename to follow Rust conventions. |

### What is not acceptable

- `#[allow(dead_code)]` on new code. If it's dead, delete it.
- `#[allow(unused_imports)]` without an explanation comment.
- Suppressing warnings with `#[allow(...)]` as a shortcut to pass CI. Fix the root cause.

The three pre-existing dead-code warnings (`Condition::new`, `Action::new`, `WatcherCmd::Shutdown`) are tracked and will be cleaned up separately — do not add to that list.

---

## Data model

Rules are stored in SQLite at `~/Library/Application Support/com.forel.app/forel.db`.

```
watched_folders (id, path, enabled, created_at)
    └── rules (id, folder_id, name, enabled, condition_match, priority, created_at)
            ├── conditions (id, rule_id, kind, operator, value)
            └── actions    (id, rule_id, kind, params JSON, position)
```

`params` is a freeform JSON object. Each action kind documents its expected keys in `action.rs`.

---

## How to add a new Action type

Actions are the most common extension point. Follow every step — skipping one silently breaks the feature.

### 1. Rust model (`src-tauri/src/rules/model.rs`)

Add a variant to `ActionKind`:
```rust
pub enum ActionKind {
    // …existing…
    YourNewAction,
}
```

### 2. Rust DB serialization (`src-tauri/src/db.rs`)

Add a string mapping in **both** converters:
```rust
// action_kind_to_str
ActionKind::YourNewAction => "your_new_action",

// parse_action_kind
"your_new_action" => ActionKind::YourNewAction,
```

### 3. Rust execution (`src-tauri/src/rules/action.rs`)

Add a match arm in `execute()`:
```rust
ActionKind::YourNewAction => {
    let param = action.params.get("my_param")
        .and_then(|v| v.as_str())
        .context("YourNewAction requires 'my_param'")?;
    // … do the thing …
}
```

### 4. TypeScript type (`src/types/index.ts`)

```typescript
export type ActionKind =
  | "your_new_action"   // ← add this
  | /* …existing… */;

export const ACTION_KIND_LABELS: Record<ActionKind, string> = {
  your_new_action: "Human readable label",
  // …
};
```

### 5. Frontend UI (`src/components/RuleEditor.tsx`)

Add a `needsX` boolean in `ActionRow` and render the relevant input(s).

---

## How to add a new Condition type

Same layered pattern as actions:

1. Add variant to `ConditionKind` in `model.rs`
2. Add string mapping in `db.rs` (`condition_kind_to_str` + `parse_condition_kind`)
3. Implement evaluation in `condition.rs` — the function receives `&Path` and returns `bool`
4. Add to `ConditionKind` union type and `CONDITION_KIND_LABELS` in `src/types/index.ts`
5. Wire up operator set in `operatorsFor()` in `RuleEditor.tsx`

---

## Tray menu

The tray menu is rebuilt from scratch after every mutation (add/remove folder, toggle rule, etc.). The entry point is `tray::rebuild(&app)` — call it at the end of any command that changes visible state.

The tray icon carries a colored status dot (green = watching, red = paused). The dot is drawn by compositing raw RGBA pixels in `tray.rs::icon_with_dot()`.

---

## AppState

```rust
pub struct AppState {
    pub db: Arc<Mutex<Connection>>,      // always lock, use, drop — don't hold across awaits
    pub watcher: Mutex<Option<WatcherHandle>>,
    pub paused: Arc<AtomicBool>,         // lock-free global pause flag
}
```

- Lock `db` for the shortest possible scope. Drop the guard before calling `tray::rebuild`.
- Send watcher commands via `state.watcher.lock()?.as_ref()?.tx.send(WatcherCmd::…)`.
- Toggle pause with `state.paused.store(…, Ordering::Relaxed)`.

---

## Code conventions

### Rust

- Edition 2021. No `extern crate` declarations needed.
- Use `anyhow::{Result, Context, bail}` for all error handling in library code.
- Commands return `Result<T, String>` — convert with `.map_err(|e| e.to_string())`.
- No `unwrap()` in production paths — use `?`, `ok()`, or `unwrap_or_default()`.
- No comments explaining *what* code does. One short comment only when *why* is non-obvious.
- No dead-code helpers. Don't add abstractions for future use.

### TypeScript / React

- Strict mode (`tsconfig.json`). No `any`.
- All `invoke()` calls go in `src/store/index.ts` — components never call `invoke` directly except in self-contained sub-components (e.g. `MacTagPicker`).
- Zustand actions are async when they wrap an `invoke`.
- Styles live in `App.css` — no CSS modules, no Tailwind, no inline styles except dynamic values (e.g. `backgroundColor`).
- Component files export one default component. Inner components (e.g. `ConditionRow`) are plain functions in the same file.
- No `useEffect` for derived state — compute it inline.

---

## PR guidelines for contributors

### Before you start

- Open an issue first for anything non-trivial. Discuss the approach before writing code.
- Check that no open PR already covers the same feature.
- `pnpm tauri dev` must run cleanly on your machine before you begin.

### What a good PR looks like

- **One concern per PR.** A new action type is one PR. A new condition type is another.
- **Both sides of the boundary.** Any PR that adds frontend UI _must_ include the matching Rust command (and vice versa). A frontend-only PR that fakes data with hardcoded values will not be merged.
- **No breaking schema changes without a migration.** If you add a column to a SQLite table, add `ALTER TABLE … ADD COLUMN` to `db::init` guarded by a `PRAGMA user_version` check, or provide a migration script.
- **`cargo check` passes** with zero new warnings — see the _Compilation warnings policy_ section above. Run `cargo check 2>&1 | grep "^warning"` and the output must be empty for lines your PR introduced.
- **`pnpm build` passes** with zero TypeScript errors.
- **Manual test.** Describe in the PR body what you tested: which folder, which file, which rule, what you observed.

### What will be rejected

- PRs that add a frontend action/condition with a stub Rust implementation.
- PRs that break the tray (the tray must reflect state changes immediately).
- PRs that add `unwrap()` calls on paths that can realistically fail.
- PRs that change `App.css` class names without updating all usages.
- PRs that add abstractions, helpers, or utilities "for later."
- Feature flags, backwards-compat shims, or commented-out code.

### Commit style

```
type: short imperative sentence

# type is one of: feat, fix, refactor, chore, docs
# Body is optional. Explain WHY, not WHAT.
```

---

## macOS-specific notes

- **Tags** are stored as a binary plist in the `com.apple.metadata:_kMDItemUserTags` xattr. The `plist` and `xattr` crates handle this. Finder reflects changes immediately — no restart needed.
- **File watching** uses FSEvents via the `notify` crate. Events arrive on a background thread; the watcher loop sends `WatcherCmd` messages over an `mpsc` channel to serialize access.
- **Tray icon** is rebuilt by compositing raw RGBA pixels. The source PNG must be square — use `sips -c <size> <size> icon.png` to crop if needed, then `pnpm tauri icon` to regenerate all sizes.
- **Window close** hides the window instead of quitting. The app keeps running in the tray. Quit is only available from the tray menu.
- This app targets **macOS only**. Do not add `#[cfg(not(target_os = "macos"))]` stubs for Linux/Windows — keep the code simple.
