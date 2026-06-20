import Testing
import Foundation
@testable import ForelCore

@Suite struct UndoPlannerTests {
    private func moveHistoryEntry(from: String, to: String, createdAt: String = ISO8601DateFormatter().string(from: Date())) -> HistoryEntry {
        let identity = FileFingerprint.identity(to)
        return HistoryEntry(
            batchId: "batch-1",
            ruleId: "rule-1",
            ruleName: "archive",
            actionKind: .moveToFolder,
            originalPath: from,
            resultPath: to,
            undo: Undo.move(from: from, to: to).toJSON(),
            reversible: true,
            status: .applied,
            createdAt: createdAt,
            resultVolumeId: identity?.volumeId,
            resultFileId: identity?.fileId
        )
    }

    @Test func safeMoveUndoRestoresTheFile() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        let entry = moveHistoryEntry(from: original, to: moved)
        let result = UndoPlanner.apply(entry, recentEvents: [])

        #expect(result.outcome == .applied)
        #expect(FileManager.default.fileExists(atPath: original))
        #expect(!FileManager.default.fileExists(atPath: moved))
    }

    @Test func moveUndoBlockedWhenOriginalPathIsOccupied() throws {
        let dir = TempDir()
        let original = dir.file("a.txt", contents: "someone else's file")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        let entry = moveHistoryEntry(from: original, to: moved)
        let result = UndoPlanner.apply(entry, recentEvents: [])

        guard case .blocked = result.outcome else {
            Issue.record("expected blocked outcome")
            return
        }
        #expect(FileManager.default.fileExists(atPath: moved))
        #expect(try String(contentsOfFile: original, encoding: .utf8) == "someone else's file")
    }

    @Test func moveUndoBlockedWhenResultFileIdentityChanged() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        // Snapshot identity for a different, already-deleted file id.
        var entry = moveHistoryEntry(from: original, to: moved)
        entry.resultFileId = (entry.resultFileId ?? 0) + 999_999

        let result = UndoPlanner.apply(entry, recentEvents: [])

        guard case .blocked = result.outcome else {
            Issue.record("expected blocked outcome")
            return
        }
        #expect(FileManager.default.fileExists(atPath: moved))
    }

    @Test func tagUndoSafeWorks() throws {
        let dir = TempDir()
        let file = dir.file("a.txt")
        try FinderTags.apply(file, tag: "Reviewed", add: true)

        let entry = HistoryEntry(
            batchId: "batch-1",
            ruleId: "rule-1",
            ruleName: "tag",
            actionKind: .addTag,
            originalPath: file,
            resultPath: file,
            undo: Undo.addTags(path: file, tags: ["Reviewed"]).toJSON(),
            reversible: true,
            status: .applied
        )
        let result = UndoPlanner.apply(entry, recentEvents: [])

        #expect(result.outcome == .applied)
        #expect(!FinderTags.read(file).contains("Reviewed"))
    }

    @Test func batchUndoAppliesInReverseOrder() throws {
        let dir = TempDir()
        let file = dir.file("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")

        let tagEntry = HistoryEntry(
            batchId: "batch-1",
            ruleId: "rule-1",
            ruleName: "tag then move",
            actionKind: .addTag,
            originalPath: file,
            resultPath: file,
            undo: Undo.addTags(path: file, tags: ["Reviewed"]).toJSON(),
            reversible: true,
            status: .applied,
            createdAt: "2026-01-01T00:00:00Z"
        )
        try FinderTags.apply(file, tag: "Reviewed", add: true)
        try FileManager.default.moveItem(atPath: file, toPath: moved)
        let moveEntry = moveHistoryEntry(from: file, to: moved, createdAt: "2026-01-01T00:00:01Z")

        let results = UndoPlanner.applyBatch([tagEntry, moveEntry], recentEvents: [])

        // Move (later) must be undone before the tag (earlier) is reachable
        // at the original path again.
        #expect(results[0].entryId == moveEntry.id)
        #expect(results[1].entryId == tagEntry.id)
        #expect(results.allSatisfy { $0.outcome == .applied })
        #expect(FileManager.default.fileExists(atPath: file))
        #expect(!FinderTags.read(file).contains("Reviewed"))
    }

    @Test func undoBlockedWhenNewerEventTouchesSameFile() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        let entry = moveHistoryEntry(from: original, to: moved, createdAt: "2026-01-01T00:00:00Z")
        let newerEvent = FilesystemEvent(
            batchId: "other-batch",
            source: .fsevents,
            kind: .modified,
            path: moved,
            createdAt: "2026-01-01T00:00:05Z"
        )

        let result = UndoPlanner.apply(entry, recentEvents: [newerEvent])

        guard case .needsConfirmation = result.outcome else {
            Issue.record("expected needsConfirmation outcome")
            return
        }
        #expect(FileManager.default.fileExists(atPath: moved))
    }

    @Test func undoBlockedWhenAnActiveRuleWouldImmediatelyReprocessTheRestoredFile() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        var archiveRule = makeRule(name: "archive txt", conditions: [makeCondition(.extension_, .is, "txt")])
        archiveRule.actions = [makeAction(.moveToFolder, .object(["destination": .string(destination)]), position: 0, ruleId: archiveRule.id)]

        let entry = moveHistoryEntry(from: original, to: moved)
        let result = UndoPlanner.apply(entry, recentEvents: [], activeRules: [archiveRule], watchedRoot: dir.path)

        guard case .blocked(let reason) = result.outcome else {
            Issue.record("expected blocked outcome")
            return
        }
        #expect(reason.contains("archive txt"))
        // Never moved back: the file must still be exactly where it was.
        #expect(FileManager.default.fileExists(atPath: moved))
        #expect(!FileManager.default.fileExists(atPath: original))
    }

    @Test func undoSafeWhenNoActiveRuleMatchesTheRestoredPath() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        var pngRule = makeRule(name: "archive png", conditions: [makeCondition(.extension_, .is, "png")])
        pngRule.actions = [makeAction(.moveToFolder, .object(["destination": .string(destination)]), position: 0, ruleId: pngRule.id)]

        let entry = moveHistoryEntry(from: original, to: moved)
        let result = UndoPlanner.apply(entry, recentEvents: [], activeRules: [pngRule], watchedRoot: dir.path)

        #expect(result.outcome == .applied)
        #expect(FileManager.default.fileExists(atPath: original))
    }

    @Test func copyUndoIgnoresActiveRulesSinceNothingIsRestored() throws {
        let dir = TempDir()
        let original = dir.file("a.txt", contents: "hi")
        let destination = dir.dir("Backup")
        let copy = (destination as NSString).appendingPathComponent("a.txt")
        try FileManager.default.copyItem(atPath: original, toPath: copy)

        // A rule that would obviously match the (untouched) original file —
        // must not block the copy-undo, since copy-undo only deletes the
        // copy and never restores anything to `originalPath`.
        var rule = makeRule(name: "archive txt", conditions: [makeCondition(.extension_, .is, "txt")])
        rule.actions = [makeAction(.moveToFolder, .object(["destination": .string(destination)]), position: 0, ruleId: rule.id)]

        let entry = HistoryEntry(
            batchId: "batch-1",
            ruleId: "rule-1",
            ruleName: "backup",
            actionKind: .copyToFolder,
            originalPath: original,
            resultPath: original,
            undo: Undo.copy(copy: copy).toJSON(),
            reversible: true,
            status: .applied
        )
        let result = UndoPlanner.apply(entry, recentEvents: [], activeRules: [rule], watchedRoot: dir.path)

        #expect(result.outcome == .applied)
        #expect(!FileManager.default.fileExists(atPath: copy))
    }

    @Test func applyBatchResolvesActiveRulesPerEntry() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        var archiveRule = makeRule(name: "archive txt", conditions: [makeCondition(.extension_, .is, "txt")])
        archiveRule.actions = [makeAction(.moveToFolder, .object(["destination": .string(destination)]), position: 0, ruleId: archiveRule.id)]

        let entry = moveHistoryEntry(from: original, to: moved)
        let results = UndoPlanner.applyBatch([entry], recentEvents: []) { _ in
            (rules: [archiveRule], watchedRoot: dir.path)
        }

        guard case .blocked = results[0].outcome else {
            Issue.record("expected blocked outcome")
            return
        }
        #expect(FileManager.default.fileExists(atPath: moved))
    }

    @Test func undoCreatesAnUndoSourcedEvent() throws {
        let dir = TempDir()
        let original = (dir.path as NSString).appendingPathComponent("a.txt")
        let destination = dir.dir("Archive")
        let moved = (destination as NSString).appendingPathComponent("a.txt")
        try "hi".write(toFile: moved, atomically: true, encoding: .utf8)

        let entry = moveHistoryEntry(from: original, to: moved)
        let result = UndoPlanner.apply(entry, recentEvents: [])

        #expect(result.events.count == 1)
        #expect(result.events[0].source == .undo)
        #expect(result.history.count == 1)
        #expect(result.history[0].undoBatchId == entry.batchId)
    }
}
