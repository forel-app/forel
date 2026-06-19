import Foundation

/// A point-in-time snapshot of a file's identity and content size/mtime, the raw
/// material the stateful watcher reasons about. Kept deliberately free of any
/// filesystem access so the decision logic below stays pure and testable.
public struct FileStat: Equatable, Sendable {
    public let sizeBytes: Int64
    public let modifiedAt: Date
    /// POSIX device id (`st_dev`); pairs with `fileId` as a persistable identity.
    public let volumeId: Int64?
    /// POSIX inode (`st_ino`).
    public let fileId: Int64?

    public init(sizeBytes: Int64, modifiedAt: Date, volumeId: Int64?, fileId: Int64?) {
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.volumeId = volumeId
        self.fileId = fileId
    }

    /// Stable, locale-independent string for the modification time, with
    /// sub-second precision so rapid successive writes are still distinguishable.
    public var modifiedAtKey: String {
        String(format: "%.6f", modifiedAt.timeIntervalSince1970)
    }

    /// Content fingerprint for new-or-changed comparison (size + mtime only — the
    /// path is never part of it; see plan D1). Matches `FileState.contentFingerprint`.
    public var contentFingerprint: String {
        FileState.contentFingerprint(sizeBytes: sizeBytes, modifiedAt: modifiedAtKey) ?? ""
    }

    /// Whether two snapshots describe the same unchanged content (used by settle).
    public func hasSameContent(as other: FileStat) -> Bool {
        sizeBytes == other.sizeBytes && modifiedAt == other.modifiedAt
    }
}

/// Reads a `FileStat` for a path. Injectable so the coordinator and tests can
/// substitute a deterministic stat source for the real filesystem.
public protocol FileStatProvider: Sendable {
    /// Returns nil when the file does not exist or cannot be statted.
    func stat(_ path: String) -> FileStat?
}

public struct SystemFileStatProvider: FileStatProvider {
    public init() {}

    public func stat(_ path: String) -> FileStat? {
        var buffer = Darwin.stat()
        guard lstat(path, &buffer) == 0 else { return nil }
        let mtime = buffer.st_mtimespec
        let interval = Double(mtime.tv_sec) + Double(mtime.tv_nsec) / 1_000_000_000
        return FileStat(
            sizeBytes: Int64(buffer.st_size),
            modifiedAt: Date(timeIntervalSince1970: interval),
            volumeId: Int64(buffer.st_dev),
            fileId: Int64(buffer.st_ino)
        )
    }
}

/// Abstracts "what time is it" so the coordinator's time-windowed logic (settle
/// ceiling, loop window) can be driven deterministically in tests.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Schedules deferred work (settle re-checks). Injectable so tests can drive
/// time deterministically instead of waiting on a real dispatch queue.
public protocol WatcherScheduler: Sendable {
    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void)
}

public struct DispatchWatcherScheduler: WatcherScheduler {
    private let queue: DispatchQueue
    public init(queue: DispatchQueue) { self.queue = queue }
    public func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Tunables for settle (waiting for a file to stop changing) and loop detection.
public struct WatcherPolicy: Sendable {
    /// First settle re-check delay; doubles each attempt up to `settleMaxDelay`.
    public var settleBaseDelay: TimeInterval
    public var settleMaxDelay: TimeInterval
    /// Total time a file may keep changing before we give up and record an error
    /// (generous on purpose so multi-GB downloads still complete — see plan D3).
    public var settleCeiling: TimeInterval
    /// Sliding window and count for runaway-reprocessing detection (plan D7).
    public var loopWindow: TimeInterval
    public var loopThreshold: Int

    public init(
        settleBaseDelay: TimeInterval = 1,
        settleMaxDelay: TimeInterval = 8,
        settleCeiling: TimeInterval = 120,
        loopWindow: TimeInterval = 60,
        loopThreshold: Int = 5
    ) {
        self.settleBaseDelay = settleBaseDelay
        self.settleMaxDelay = settleMaxDelay
        self.settleCeiling = settleCeiling
        self.loopWindow = loopWindow
        self.loopThreshold = loopThreshold
    }

    public static let `default` = WatcherPolicy()

    /// Backoff delay for settle re-check number `attempt` (0-based).
    public func settleDelay(attempt: Int) -> TimeInterval {
        let raw = settleBaseDelay * pow(2, Double(max(0, attempt)))
        return min(raw, settleMaxDelay)
    }
}

/// Outcome of checking whether a file has stopped changing.
public enum SettleOutcome: Equatable, Sendable {
    /// File has been stable across two observations — ready to evaluate.
    case stable
    /// Still changing (or first observation); re-check after `nextDelay`.
    case keepWaiting(nextDelay: TimeInterval)
    /// File no longer exists.
    case vanished
    /// Kept changing past `settleCeiling`; stop waiting and record an error.
    case giveUp
}

/// Outcome of the new-or-changed + loop gate for an automatic run.
public enum ProcessOutcome: Equatable, Sendable {
    case process
    case skipUnchanged
    case loopBlocked
}

/// Pure decision logic for the stateful watcher. No filesystem, no timers, no
/// database — every input is passed in, so each branch is unit-testable.
public enum WatcherDecision {
    /// File extensions used by browsers/clients for in-progress downloads; the
    /// watcher waits for the rename to the final name instead (plan D3).
    public static let ignoredExtensions: Set<String> = ["crdownload", "download", "part", "tmp"]

    /// Whether a path should be skipped entirely: invisible files (incl.
    /// `.DS_Store`) and in-progress download temp files.
    public static func shouldIgnore(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name.hasPrefix(".") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return ignoredExtensions.contains(ext)
    }

    /// Decides whether a file has settled, given the previous observation (nil on
    /// the first check), the current one (nil if it vanished), how many checks
    /// have already happened, and how long we've been waiting in total.
    public static func settle(
        previous: FileStat?,
        current: FileStat?,
        attempt: Int,
        elapsed: TimeInterval,
        policy: WatcherPolicy = .default
    ) -> SettleOutcome {
        guard let current else { return .vanished }
        if let previous, previous.hasSameContent(as: current) {
            return .stable
        }
        if elapsed >= policy.settleCeiling {
            return .giveUp
        }
        return .keepWaiting(nextDelay: policy.settleDelay(attempt: attempt))
    }

    /// Decides whether an automatic run should execute the rules, skip (already
    /// processed, unchanged), or be blocked because the file is looping. `stat`
    /// is the settled current snapshot; `recentRuns` holds the timestamps of this
    /// file's recent automatic executions.
    public static func processDecision(
        fileState: FileState?,
        stat: FileStat,
        recentRuns: [Date],
        now: Date,
        policy: WatcherPolicy = .default
    ) -> ProcessOutcome {
        let runsInWindow = recentRuns.filter { now.timeIntervalSince($0) < policy.loopWindow }.count
        if runsInWindow >= policy.loopThreshold {
            return .loopBlocked
        }
        if let fileState, fileState.contentFingerprint == stat.contentFingerprint {
            return .skipUnchanged
        }
        return .process
    }
}
