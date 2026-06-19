import Testing
import Foundation
@testable import ForelCore

@Suite struct WatcherDecisionTests {
    private func stat(size: Int64, mtime: TimeInterval, volumeId: Int64? = 1, fileId: Int64? = 100) -> FileStat {
        FileStat(sizeBytes: size, modifiedAt: Date(timeIntervalSince1970: mtime), volumeId: volumeId, fileId: fileId)
    }

    // MARK: - FileStat fingerprint parity (plan D1)

    @Test func fileStatFingerprintMatchesFileStateHelper() {
        let s = stat(size: 100, mtime: 1_700_000_000)
        let expected = FileState.contentFingerprint(sizeBytes: 100, modifiedAt: s.modifiedAtKey)
        #expect(s.contentFingerprint == expected)
    }

    @Test func fileStatModifiedKeyIsLocaleIndependentDecimal() {
        let s = stat(size: 1, mtime: 1_700_000_000.5)
        #expect(s.modifiedAtKey.contains("."))
        #expect(!s.modifiedAtKey.contains(","))
    }

    // MARK: - Settle (plan D3)

    @Test func settleFirstObservationKeepsWaiting() {
        let outcome = WatcherDecision.settle(previous: nil, current: stat(size: 10, mtime: 1), attempt: 0, elapsed: 0)
        #expect(outcome == .keepWaiting(nextDelay: 1))
    }

    @Test func settleStableWhenTwoObservationsMatch() {
        let snap = stat(size: 10, mtime: 1)
        let outcome = WatcherDecision.settle(previous: snap, current: snap, attempt: 1, elapsed: 1)
        #expect(outcome == .stable)
    }

    @Test func settleKeepsWaitingWhileFileStillGrowing() {
        let outcome = WatcherDecision.settle(
            previous: stat(size: 10, mtime: 1),
            current: stat(size: 20, mtime: 2),
            attempt: 2,
            elapsed: 3
        )
        #expect(outcome == .keepWaiting(nextDelay: 4))
    }

    @Test func settleVanishedWhenCurrentMissing() {
        let outcome = WatcherDecision.settle(previous: stat(size: 10, mtime: 1), current: nil, attempt: 1, elapsed: 1)
        #expect(outcome == .vanished)
    }

    @Test func settleGivesUpAfterCeilingWhenStillUnstable() {
        let outcome = WatcherDecision.settle(
            previous: stat(size: 10, mtime: 1),
            current: stat(size: 30, mtime: 9),
            attempt: 9,
            elapsed: 121
        )
        #expect(outcome == .giveUp)
    }

    @Test func settleStablePreemptsCeiling() {
        // Even past the ceiling, a stable file is processed, not given up on.
        let snap = stat(size: 10, mtime: 1)
        let outcome = WatcherDecision.settle(previous: snap, current: snap, attempt: 9, elapsed: 500)
        #expect(outcome == .stable)
    }

    @Test func settleBackoffDoublesAndCaps() {
        let policy = WatcherPolicy.default
        #expect(policy.settleDelay(attempt: 0) == 1)
        #expect(policy.settleDelay(attempt: 1) == 2)
        #expect(policy.settleDelay(attempt: 2) == 4)
        #expect(policy.settleDelay(attempt: 3) == 8)
        #expect(policy.settleDelay(attempt: 4) == 8) // capped at settleMaxDelay
    }

    // MARK: - New-or-changed + loop (plan D1/D7)

    @Test func processDecisionProcessesNewFile() {
        let outcome = WatcherDecision.processDecision(
            fileState: nil, stat: stat(size: 10, mtime: 1), recentRuns: [], now: Date()
        )
        #expect(outcome == .process)
    }

    @Test func processDecisionSkipsUnchangedFile() {
        let s = stat(size: 10, mtime: 1)
        var state = FileState(folderId: "f", path: "/x")
        state.contentFingerprint = s.contentFingerprint
        let outcome = WatcherDecision.processDecision(
            fileState: state, stat: s, recentRuns: [], now: Date()
        )
        #expect(outcome == .skipUnchanged)
    }

    @Test func processDecisionProcessesChangedFile() {
        var state = FileState(folderId: "f", path: "/x")
        state.contentFingerprint = stat(size: 10, mtime: 1).contentFingerprint
        let outcome = WatcherDecision.processDecision(
            fileState: state, stat: stat(size: 20, mtime: 2), recentRuns: [], now: Date()
        )
        #expect(outcome == .process)
    }

    @Test func processDecisionBlocksLoopWithinWindow() {
        let now = Date()
        let recent = (1...5).map { now.addingTimeInterval(-Double($0)) } // 5 runs in last 5s
        let outcome = WatcherDecision.processDecision(
            fileState: nil, stat: stat(size: 10, mtime: 1), recentRuns: recent, now: now
        )
        #expect(outcome == .loopBlocked)
    }

    @Test func processDecisionIgnoresRunsOutsideWindow() {
        let now = Date()
        // 5 runs, but all older than the 60s loop window → not a loop.
        let stale = (1...5).map { now.addingTimeInterval(-60 - Double($0)) }
        let outcome = WatcherDecision.processDecision(
            fileState: nil, stat: stat(size: 10, mtime: 1), recentRuns: stale, now: now
        )
        #expect(outcome == .process)
    }

    // MARK: - SystemFileStatProvider

    @Test func systemStatProviderReadsRealFileAndMissingReturnsNil() throws {
        let dir = TempDir()
        let path = dir.file("data.bin", contents: "hello world")
        let provider = SystemFileStatProvider()

        let s = try #require(provider.stat(path))
        #expect(s.sizeBytes == 11)
        #expect(s.fileId != nil)
        #expect(s.volumeId != nil)

        #expect(provider.stat((dir.path as NSString).appendingPathComponent("nope.bin")) == nil)
    }
}
