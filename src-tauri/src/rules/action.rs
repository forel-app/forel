use std::path::Path;

use anyhow::{bail, Context, Result};

use super::model::{Action, ActionKind};

/// Executes the action on the file at `path`.
pub fn execute(action: &Action, path: &Path) -> Result<()> {
    match &action.kind {
        ActionKind::MoveToFolder => {
            let dest_dir = action
                .params
                .get("destination")
                .and_then(|v| v.as_str())
                .context("MoveToFolder requires 'destination' param")?;
            let file_name = path.file_name().context("no file name")?;
            let dest = Path::new(dest_dir).join(file_name);
            std::fs::rename(path, &dest)
                .with_context(|| format!("move {:?} → {:?}", path, dest))?;
        }

        ActionKind::CopyToFolder => {
            let dest_dir = action
                .params
                .get("destination")
                .and_then(|v| v.as_str())
                .context("CopyToFolder requires 'destination' param")?;
            let file_name = path.file_name().context("no file name")?;
            let dest = Path::new(dest_dir).join(file_name);
            std::fs::copy(path, &dest)
                .with_context(|| format!("copy {:?} → {:?}", path, dest))?;
        }

        ActionKind::Rename => {
            let pattern = action
                .params
                .get("pattern")
                .and_then(|v| v.as_str())
                .context("Rename requires 'pattern' param")?;
            let new_name = apply_rename_pattern(pattern, path)?;
            let dest = path.with_file_name(new_name);
            std::fs::rename(path, &dest)
                .with_context(|| format!("rename {:?} → {:?}", path, dest))?;
        }

        ActionKind::MoveToTrash => {
            // On macOS, move to ~/.Trash
            let file_name = path.file_name().context("no file name")?;
            let trash = dirs_next()?;
            let dest = trash.join(file_name);
            std::fs::rename(path, &dest)?;
        }

        ActionKind::Delete => {
            if path.is_dir() {
                std::fs::remove_dir_all(path)?;
            } else {
                std::fs::remove_file(path)?;
            }
        }

        ActionKind::AddTag => {
            let tag = action
                .params
                .get("tag")
                .and_then(|v| v.as_str())
                .context("AddTag requires 'tag' param")?;
            apply_file_tag(path, tag, true)?;
        }

        ActionKind::RemoveTag => {
            let tag = action
                .params
                .get("tag")
                .and_then(|v| v.as_str())
                .context("RemoveTag requires 'tag' param")?;
            apply_file_tag(path, tag, false)?;
        }

        ActionKind::SetColorLabel => {
            let color = action
                .params
                .get("color")
                .and_then(|v| v.as_str())
                .context("SetColorLabel requires 'color' param")?;
            set_color_label(path, color)?;
        }

        ActionKind::RunScript => {
            let script = action
                .params
                .get("script")
                .and_then(|v| v.as_str())
                .context("RunScript requires 'script' param")?;
            std::process::Command::new("bash")
                .args(["-c", script])
                .env("FOREL_FILE", path)
                .spawn()?;
        }
    }

    Ok(())
}

/// Substitutes tokens in rename patterns.
/// Supported tokens: {name}, {extension}, {date_created}, {date_modified}
fn apply_rename_pattern(pattern: &str, path: &Path) -> Result<String> {
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("");

    let meta = std::fs::metadata(path)?;
    let modified: chrono::DateTime<chrono::Local> = meta.modified()?.into();
    let created: chrono::DateTime<chrono::Local> = meta.created()?.into();

    let result = pattern
        .replace("{name}", stem)
        .replace("{extension}", ext)
        .replace("{date_modified}", &modified.format("%Y-%m-%d").to_string())
        .replace("{date_created}", &created.format("%Y-%m-%d").to_string());

    if result.is_empty() {
        bail!("rename pattern produced empty filename");
    }

    if ext.is_empty() {
        Ok(result)
    } else {
        Ok(format!("{}.{}", result, ext))
    }
}

#[cfg(target_os = "macos")]
fn dirs_next() -> Result<std::path::PathBuf> {
    let home = std::env::var("HOME").context("HOME not set")?;
    Ok(std::path::PathBuf::from(home).join(".Trash"))
}

#[cfg(not(target_os = "macos"))]
fn dirs_next() -> Result<std::path::PathBuf> {
    bail!("trash is only implemented on macOS")
}

// ---------- macOS Finder tags via xattr ----------

const TAGS_XATTR: &str = "com.apple.metadata:_kMDItemUserTags";

/// Reads the Finder tags on `path`, or an empty list if there are none.
///
/// Tags are stored as a binary-plist–encoded `Vec<String>` in the extended
/// attribute `com.apple.metadata:_kMDItemUserTags`. A color label is just a
/// tag whose name matches a system colour (sometimes suffixed with "\nN").
pub fn read_file_tags(path: &Path) -> Vec<String> {
    xattr::get(path, TAGS_XATTR)
        .ok()
        .flatten()
        .and_then(|bytes| plist::from_bytes::<Vec<String>>(&bytes).ok())
        .unwrap_or_default()
}

/// Serialises `tags` to a binary plist and writes them to the xattr.
fn write_file_tags(path: &Path, tags: &[String]) -> Result<()> {
    let mut buf: Vec<u8> = Vec::new();
    plist::to_writer_binary(std::io::Cursor::new(&mut buf), &tags)
        .context("failed to serialise tags plist")?;
    xattr::set(path, TAGS_XATTR, &buf).context("failed to write tags xattr")?;
    Ok(())
}

/// Adds or removes a named Finder tag on `path`. Finder reads tags live so the
/// change is visible immediately without any Finder restart.
fn apply_file_tag(path: &Path, tag: &str, add: bool) -> Result<()> {
    let mut tags = read_file_tags(path);

    if add {
        if !tags.iter().any(|t| t == tag) {
            tags.push(tag.to_string());
        }
    } else {
        tags.retain(|t| t != tag);
    }

    write_file_tags(path, &tags)
}

/// Finder colour-label index for each of the 7 system colours.
fn color_index(name: &str) -> Option<u8> {
    match name.to_lowercase().as_str() {
        "gray" | "grey" => Some(1),
        "green" => Some(2),
        "purple" => Some(3),
        "blue" => Some(4),
        "yellow" => Some(5),
        "red" => Some(6),
        "orange" => Some(7),
        _ => None,
    }
}

/// Sets the macOS colour label on `path`, replacing any existing colour label.
///
/// Finder stores a colour label as a tag of the form `"Name\nIndex"`. We drop
/// any existing system-colour tag first so a file has at most one colour, then
/// add the new one. An empty/`"none"` colour just clears the label.
fn set_color_label(path: &Path, color: &str) -> Result<()> {
    let mut tags = read_file_tags(path);

    // Remove any existing colour-label tag (a tag whose name is a system colour).
    tags.retain(|t| {
        let name = t.split('\n').next().unwrap_or(t).trim();
        color_index(name).is_none()
    });

    if let Some(idx) = color_index(color) {
        tags.push(format!("{}\n{}", capitalize(color), idx));
    }

    write_file_tags(path, &tags)
}

fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + &chars.as_str().to_lowercase(),
        None => String::new(),
    }
}
