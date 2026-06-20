import Foundation

/// Whether undoing one `HistoryEntry` is safe to apply automatically.
public enum UndoSafety: Equatable, Sendable {
    case safe
    /// Reversing this entry would be wrong or impossible; never apply.
    case unsafeToUndo(reason: String)
    /// Something changed since the action ran that the user should
    /// confirm before Forel reverses it.
    case needsConfirmation(reason: String)
}

public enum UndoOutcome: Equatable, Sendable {
    case applied
    case blocked(reason: String)
    case needsConfirmation(reason: String)
}

/// What undoing one entry produced: the new journal/history rows to persist
/// alongside marking the original entry `undone`.
public struct UndoExecutionResult: Sendable {
    public let entryId: String
    public let outcome: UndoOutcome
    public let history: [HistoryEntry]
    public let events: [FilesystemEvent]
}

/// Decides whether reversing a past action is safe, and performs it when it
/// is — never a silent best-effort rollback on a file that no longer
/// matches what Forel originally changed.
public enum UndoPlanner {
    /// `recentEvents` should be every `FilesystemEvent` Forel has observed
    /// for `entry.resultPath` (or the identity it last had), so a change
    /// that happened after this action can be detected.
    ///
    /// `activeRules`/`watchedRoot` are the enabled rules and watched-folder
    /// root currently covering `entry.originalPath`, if any — pass them so
    /// undo refuses to put a file right back somewhere an active rule would
    /// immediately reprocess it (the watcher would otherwise just redo what
    /// the user explicitly asked to undo).
    public static func evaluate(
        _ entry: HistoryEntry,
        recentEvents: [FilesystemEvent],
        activeRules: [Rule] = [],
        watchedRoot: String? = nil
    ) -> UndoSafety {
        guard entry.reversible else {
            return .unsafeToUndo(reason: "This action cannot be undone.")
        }
        guard entry.status == .applied else {
            return .unsafeToUndo(reason: "This action is not currently applied.")
        }

        let undo = Undo.fromJSON(entry.undo)
        switch undo {
        case .none:
            return .unsafeToUndo(reason: "This action cannot be undone.")
        case .move(let from, let to):
            guard FileManager.default.fileExists(atPath: to) else {
                return .unsafeToUndo(reason: "The file Forel moved no longer exists at \((to as NSString).lastPathComponent).")
            }
            guard !FileManager.default.fileExists(atPath: from) else {
                return .unsafeToUndo(reason: "A file already exists at the original location.")
            }
            if let identityMismatch = identityChanged(entry, currentPath: to) {
                return .unsafeToUndo(reason: identityMismatch)
            }
        case .copy(let copy):
            guard FileManager.default.fileExists(atPath: copy) else {
                return .unsafeToUndo(reason: "The copy Forel created no longer exists.")
            }
        case .addTags, .removeTags, .color:
            guard FileManager.default.fileExists(atPath: entry.resultPath) else {
                return .unsafeToUndo(reason: "The file no longer exists at its expected location.")
            }
        }

        // Copy-undo only deletes the copy; the original file is never
        // restored anywhere, so there's nothing for a rule to reprocess.
        if !isCopyUndo(undo), let ruleName = ruleThatWouldReprocess(entry, activeRules: activeRules, watchedRoot: watchedRoot) {
            return .unsafeToUndo(reason: "The rule \"\(ruleName)\" would immediately reprocess this file once it's restored.")
        }

        if let newerEvent = recentEvents.first(where: { isNewerThanAction($0, entry: entry) }) {
            return .needsConfirmation(reason: "Forel saw another change to this file after this action (\(newerEvent.kind.rawValue)).")
        }

        return .safe
    }

    /// Reverses `entry` if it's safe (or `allowNeedsConfirmation` and it
    /// merely needs confirmation), recording a new history entry/event for
    /// the undo itself. Never mutates the filesystem when blocked.
    public static func apply(
        _ entry: HistoryEntry,
        recentEvents: [FilesystemEvent],
        activeRules: [Rule] = [],
        watchedRoot: String? = nil,
        allowNeedsConfirmation: Bool = false
    ) -> UndoExecutionResult {
        let safety = evaluate(entry, recentEvents: recentEvents, activeRules: activeRules, watchedRoot: watchedRoot)
        switch safety {
        case .unsafeToUndo(let reason):
            return UndoExecutionResult(entryId: entry.id, outcome: .blocked(reason: reason), history: [], events: [])
        case .needsConfirmation(let reason) where !allowNeedsConfirmation:
            return UndoExecutionResult(entryId: entry.id, outcome: .needsConfirmation(reason: reason), history: [], events: [])
        case .needsConfirmation, .safe:
            break
        }

        do {
            try ActionExecutor.revert(Undo.fromJSON(entry.undo))
        } catch {
            return UndoExecutionResult(entryId: entry.id, outcome: .blocked(reason: String(describing: error)), history: [], events: [])
        }

        let undoBatchId = UUID().uuidString
        let undoEntry = HistoryEntry(
            batchId: undoBatchId,
            ruleId: entry.ruleId,
            ruleName: entry.ruleName,
            actionKind: entry.actionKind,
            originalPath: entry.resultPath,
            resultPath: entry.originalPath,
            undo: Undo.none.toJSON(),
            reversible: false,
            status: .applied,
            message: "Undo of a previous \(entry.actionKind.rawValue) action.",
            undoBatchId: entry.batchId
        )
        let undoEvent = FilesystemEvent(
            batchId: undoBatchId,
            source: .undo,
            kind: .renamed,
            path: entry.originalPath,
            previousPath: entry.resultPath,
            contentFingerprint: FileFingerprint.current(entry.originalPath),
            isForelOriginated: true
        )
        return UndoExecutionResult(entryId: entry.id, outcome: .applied, history: [undoEntry], events: [undoEvent])
    }

    /// Undoes a batch in reverse chronological order, the same order their
    /// effects must be peeled back in. `activeRules` resolves the enabled
    /// rules/watched-root covering each entry's original path individually,
    /// since a batch can span multiple watched folders.
    public static func applyBatch(
        _ entries: [HistoryEntry],
        recentEvents: [FilesystemEvent],
        allowNeedsConfirmation: Bool = false,
        activeRules: (HistoryEntry) -> (rules: [Rule], watchedRoot: String?) = { _ in ([], nil) }
    ) -> [UndoExecutionResult] {
        entries
            .sorted { $0.createdAt > $1.createdAt }
            .map { entry in
                let context = activeRules(entry)
                return apply(
                    entry,
                    recentEvents: recentEvents,
                    activeRules: context.rules,
                    watchedRoot: context.watchedRoot,
                    allowNeedsConfirmation: allowNeedsConfirmation
                )
            }
    }

    private static func identityChanged(_ entry: HistoryEntry, currentPath: String) -> String? {
        guard let expectedVolume = entry.resultVolumeId, let expectedFile = entry.resultFileId else { return nil }
        guard let actual = FileFingerprint.identity(currentPath) else { return nil }
        guard actual.volumeId != expectedVolume || actual.fileId != expectedFile else { return nil }
        return "The file at this location is no longer the same file Forel moved."
    }

    private static func isNewerThanAction(_ event: FilesystemEvent, entry: HistoryEntry) -> Bool {
        guard event.batchId != entry.batchId else { return false }
        guard event.createdAt > entry.createdAt else { return false }
        guard !event.isForelOriginated else { return false }
        return true
    }

    private static func isCopyUndo(_ undo: Undo) -> Bool {
        if case .copy = undo { return true }
        return false
    }

    /// Name of the first active rule that would plan a `wouldRun` action
    /// against `entry.originalPath` if the file were there right now.
    /// `name`/`extension` conditions work from the path string alone, so
    /// this is accurate for them even though the file doesn't physically
    /// exist there yet; conditions that read the file itself (size, tags,
    /// dates, contents) just won't match before the restore actually
    /// happens, which only means a rule keyed on those won't be caught here.
    private static func ruleThatWouldReprocess(_ entry: HistoryEntry, activeRules: [Rule], watchedRoot: String?) -> String? {
        guard let watchedRoot, !activeRules.isEmpty else { return nil }
        guard let depth = RuleEngine.pathDepth(root: watchedRoot, path: entry.originalPath) else { return nil }
        guard let rematch = RulePlanner.planFile(path: entry.originalPath, depth: depth, rules: activeRules, root: watchedRoot) else {
            return nil
        }
        return rematch.rules.first { $0.actions.contains { $0.status == .wouldRun } }?.ruleName
    }
}
