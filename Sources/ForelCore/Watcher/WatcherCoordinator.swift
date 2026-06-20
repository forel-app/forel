import CoreServices
import Foundation

/// Wires `FileWatcher` events to the database and rule engine: for every
/// created/renamed path, finds the owning watched folder, loads its rules,
/// evaluates them, and persists any resulting action history. Mirrors
/// `watcher::on_event` / `load_folder_and_rules_for_path`.
public final class WatcherCoordinator: @unchecked Sendable {
    private let db: Database
    private let watcher: FileWatcher
    public var onRuleMatched: (@Sendable (String, String) -> Void)?

    public init(db: Database) {
        self.db = db
        var watcherRef: FileWatcher!
        watcherRef = FileWatcher(onEvent: { _, _ in })
        self.watcher = watcherRef
        self.watcher.replaceHandler { [weak self] path, flags in
            self?.handle(path: path, flags: flags)
        }
    }

    public func add(_ path: String) { watcher.add(path) }
    public func remove(_ path: String) { watcher.remove(path) }

    /// Catches up on files that changed while Forel wasn't running (missed
    /// FSEvents) by planning and executing the folder's rules against every
    /// file currently in scope — the same pipeline a manual Run Now uses.
    /// Safe to call repeatedly: rules already satisfied simply plan to
    /// `wouldSkip`.
    public func runStartupScan(folder: WatchedFolder) {
        let rules = db.withLock { db in (try? db.listRules(folderId: folder.id)) ?? [] }
        guard !rules.isEmpty else { return }

        let maxDepth = RuleEngine.maxRuleDepth(rules)
        let entries = RuleEngine.walkEntries(root: folder.path, maxDepth: maxDepth)
        let scanBatchId = UUID().uuidString
        let scanEvents = entries.map { entry in
            FilesystemEvent(batchId: scanBatchId, source: .scan, kind: .discovered, path: entry.path)
        }
        db.withLock { db in try? db.insertFilesystemEvents(scanEvents) }

        let plan = RulePlanner.plan(entries: entries, rules: rules, root: folder.path, folderId: folder.id, status: .ready)
        persist(PlanExecutor.execute(plan))
    }

    func handle(path: String, flags: UInt32) {
        journalFSEvent(path: path, flags: flags)

        // A duplicate/coalesced FSEvent for a path a prior (serial) call
        // already moved away — common with FSEvents — would otherwise be
        // planned anew (name/extension conditions don't require the file to
        // exist) and then fail at execution with a noisy "source file no
        // longer exists" entry. Nothing meaningful can be evaluated against
        // a path that's already gone, so just stop here.
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard hasFileChangedSinceLastEvaluation(path) else { return }

        guard let (folder, rules) = db.withLock({ db -> (WatchedFolder, [Rule])? in
            guard let folder = try? db.folderForPath(path) else { return nil }
            let rules = (try? db.listRules(folderId: folder.id)) ?? []
            return (folder, rules)
        }) else { return }

        guard let depth = RuleEngine.pathDepth(root: folder.path, path: path) else { return }
        guard let plannedFile = RulePlanner.planFile(path: path, depth: depth, rules: rules, root: folder.path) else {
            recordEvaluatedState(path)
            return
        }

        for plannedRule in plannedFile.rules {
            onRuleMatched?(plannedRule.ruleName, path)
        }

        let plan = ExecutionPlan(folderId: folder.id, status: .ready, files: [plannedFile])
        persist(PlanExecutor.execute(plan))
        recordEvaluatedState(path)
    }

    private func persist(_ result: PlanExecutionResult) {
        guard !result.history.isEmpty else { return }
        db.withLock { db in
            try? db.insertHistoryEntries(result.history)
            try? db.insertFilesystemEvents(result.events)
            for state in result.fileStateUpserts { try? db.upsertFileState(state) }
            for path in result.fileStateDeletes { try? db.deleteFileState(path) }
        }
    }

    /// Whether `path` looks different from the last time the watcher fully
    /// evaluated it (same identity and content fingerprint means nothing
    /// meaningful changed). Without this, an action that doesn't move the
    /// file out of scope — `copyToFolder` in particular, which has no
    /// `alreadyInDestination`-style no-op the way `moveToFolder` does —
    /// would repeat itself on every duplicate/coalesced FSEvent for the same
    /// untouched source, piling up copies indefinitely.
    ///
    /// This checks the *observed* path itself, not anything an action
    /// produced, so a path nothing has evaluated before — e.g. a file a
    /// previous rule just moved here — always proceeds; only a path whose
    /// own state we've already fully evaluated gets skipped.
    private func hasFileChangedSinceLastEvaluation(_ path: String) -> Bool {
        guard let cached = db.withLock({ db in try? db.getWatcherEvaluatedState(path) }) else { return true }
        guard let currentFingerprint = FileFingerprint.current(path), cached.contentFingerprint == currentFingerprint else {
            return true
        }
        guard let volumeId = cached.volumeId, let fileId = cached.fileId else { return true }
        guard let identity = FileFingerprint.identity(path) else { return true }
        return !(identity.volumeId == volumeId && identity.fileId == fileId)
    }

    private func recordEvaluatedState(_ path: String) {
        // Nothing meaningful to cache once the file's gone (e.g. it was
        // just moved away) — and caching a path's only-just-vacated state
        // would just be inert until something new shows up there anyway.
        guard FileManager.default.fileExists(atPath: path) else { return }
        let identity = FileFingerprint.identity(path)
        let state = FileState(
            path: path,
            volumeId: identity?.volumeId,
            fileId: identity?.fileId,
            contentFingerprint: FileFingerprint.current(path)
        )
        db.withLock { db in try? db.upsertWatcherEvaluatedState(state) }
    }

    /// Records the raw FSEvents flag for `path` so the journal distinguishes
    /// observed facts from Forel's own planning/execution later.
    private func journalFSEvent(path: String, flags: UInt32) {
        let identity = FileFingerprint.identity(path)
        let event = FilesystemEvent(
            source: .fsevents,
            kind: WatcherCoordinator.kind(forFlags: flags),
            path: path,
            volumeId: identity?.volumeId,
            fileId: identity?.fileId,
            contentFingerprint: FileFingerprint.current(path),
            rawFlags: Int64(flags)
        )
        db.withLock { db in
            try? db.insertFilesystemEvent(event)
        }
    }

    static func kind(forFlags flags: UInt32) -> FilesystemEventKind {
        if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return .renamed }
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return .created }
        return .unknown
    }
}
