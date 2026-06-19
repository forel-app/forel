import Testing
import Foundation
import SQLite3
@testable import ForelCore

@Suite struct FileStateTests {
    private func makeDB() throws -> Database {
        try Database(path: ":memory:")
    }

    private func insertedFolder(_ db: Database) throws -> WatchedFolder {
        let folder = WatchedFolder(path: "/tmp/forel-test-\(UUID().uuidString)")
        try db.insertFolder(folder)
        return folder
    }

    private func readUserVersion(_ path: String) -> Int64 {
        var raw: OpaquePointer?
        guard sqlite3_open(path, &raw) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(raw) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(raw, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int64(stmt, 0)
    }

    // MARK: - Content fingerprint (plan D1)

    @Test func contentFingerprintIsStableAndContentSensitive() {
        let base = FileState.contentFingerprint(sizeBytes: 100, modifiedAt: "2026-06-19T10:00:00Z")
        let same = FileState.contentFingerprint(sizeBytes: 100, modifiedAt: "2026-06-19T10:00:00Z")
        let biggerSize = FileState.contentFingerprint(sizeBytes: 101, modifiedAt: "2026-06-19T10:00:00Z")
        let newerMtime = FileState.contentFingerprint(sizeBytes: 100, modifiedAt: "2026-06-19T11:00:00Z")
        #expect(base != nil)
        #expect(base == same)
        #expect(base != biggerSize)
        #expect(base != newerMtime)
    }

    @Test func contentFingerprintNilWhenStatMissing() {
        #expect(FileState.contentFingerprint(sizeBytes: nil, modifiedAt: "2026-06-19T10:00:00Z") == nil)
        #expect(FileState.contentFingerprint(sizeBytes: 100, modifiedAt: nil) == nil)
    }

    // MARK: - Migration v6

    @Test func freshDatabaseHasUsableFileStateTable() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/a.txt"))
        #expect(try db.fileStateForPath("/tmp/forel/a.txt") != nil)
        #expect(try db.listFileStates(folderId: folder.id).count == 1)
    }

    @Test func migrationV6PreservesExistingDataAndBumpsVersion() throws {
        let path = NSTemporaryDirectory().appending("forel-db-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let folder = WatchedFolder(path: "/tmp/forel-\(UUID().uuidString)")
        let rule = makeRule(folderId: folder.id, name: "keep me")
        let history = HistoryEntry(
            batchId: "batch", ruleId: rule.id, ruleName: "keep me", actionKind: .moveToFolder,
            originalPath: "/a", resultPath: "/b", undo: .object(["kind": .string("none")]), reversible: false
        )

        do {
            let db = try Database(path: path)
            try db.insertFolder(folder)
            try db.insertRule(rule)
            try db.insertHistoryEntries([history])
        }

        // Simulate a pre-v6 database on disk: drop file_state and roll the
        // schema version back to 5, leaving folders/rules/history intact.
        var raw: OpaquePointer?
        #expect(sqlite3_open(path, &raw) == SQLITE_OK)
        #expect(sqlite3_exec(raw, "DROP TABLE file_state; PRAGMA user_version = 5;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(raw)

        let db = try Database(path: path)
        #expect(readUserVersion(path) == Database.currentSchemaVersion)
        #expect(try db.listFolders().map(\.id) == [folder.id])
        #expect(try db.listRules(folderId: folder.id).map(\.name) == ["keep me"])
        #expect(try db.listHistory().count == 1)

        // file_state is usable again after the migration recreated it.
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/x.txt"))
        #expect(try db.fileStateForPath("/tmp/forel/x.txt") != nil)
    }

    @Test func deletingFolderCascadesFileState() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/a.txt"))

        try db.deleteFolder(folder.id)

        #expect(try db.listFileStates(folderId: folder.id).isEmpty)
        #expect(try db.fileStateForPath("/tmp/forel/a.txt") == nil)
    }

    // MARK: - Identity lookup (plan D1/D5)

    @Test func fileStateFoundByIdentityAfterRename() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        let state = FileState(
            folderId: folder.id, volumeId: 42, fileId: 1001,
            path: "/tmp/forel/old.txt", contentFingerprint: "100:t"
        )
        try db.upsertFileState(state)

        let found = try db.fileStateForIdentity(volumeId: 42, fileId: 1001)
        #expect(found?.path == "/tmp/forel/old.txt")
        #expect(found?.contentFingerprint == "100:t")
    }

    @Test func identityLookupNilWhenIdentityMissingButPathStillWorks() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/a.txt"))

        #expect(try db.fileStateForIdentity(volumeId: nil, fileId: nil) == nil)
        #expect(try db.fileStateForIdentity(volumeId: 1, fileId: 1) == nil)
        #expect(try db.fileStateForPath("/tmp/forel/a.txt") != nil)
    }

    // MARK: - Upsert semantics

    @Test func upsertPreservesFirstSeenAndRowIdOnConflict() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        let first = FileState(
            folderId: folder.id, path: "/tmp/forel/a.txt",
            firstSeenAt: "2026-01-01T00:00:00Z", lastSeenAt: "2026-01-01T00:00:00Z"
        )
        try db.upsertFileState(first)

        var second = first
        second.id = UUID().uuidString
        second.firstSeenAt = "2026-06-19T00:00:00Z"
        second.lastSeenAt = "2026-06-19T00:00:00Z"
        try db.upsertFileState(second)

        let loaded = try #require(try db.fileStateForPath("/tmp/forel/a.txt"))
        #expect(loaded.firstSeenAt == "2026-01-01T00:00:00Z")
        #expect(loaded.lastSeenAt == "2026-06-19T00:00:00Z")
        #expect(loaded.id == first.id)
    }

    // MARK: - Processing result / error

    @Test func recordProcessingResultStoresFingerprintAndClearsError() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/a.txt"))

        try db.recordFileProcessingError(path: "/tmp/forel/a.txt", error: "boom", at: "2026-06-19T09:00:00Z")
        #expect(try db.fileStateForPath("/tmp/forel/a.txt")?.lastError == "boom")

        try db.recordFileProcessingResult(
            path: "/tmp/forel/a.txt", contentFingerprint: "100:t", sizeBytes: 100,
            modifiedAt: "2026-06-19T10:00:00Z", matched: true, at: "2026-06-19T10:00:00Z"
        )
        let loaded = try #require(try db.fileStateForPath("/tmp/forel/a.txt"))
        #expect(loaded.contentFingerprint == "100:t")
        #expect(loaded.sizeBytes == 100)
        #expect(loaded.lastProcessedAt == "2026-06-19T10:00:00Z")
        #expect(loaded.lastMatchedAt == "2026-06-19T10:00:00Z")
        #expect(loaded.lastError == nil)
    }

    @Test func recordProcessingResultWithoutMatchKeepsPriorLastMatched() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/a.txt"))

        try db.recordFileProcessingResult(
            path: "/tmp/forel/a.txt", contentFingerprint: "1:t", sizeBytes: 1,
            modifiedAt: "t", matched: true, at: "2026-06-19T10:00:00Z"
        )
        try db.recordFileProcessingResult(
            path: "/tmp/forel/a.txt", contentFingerprint: "2:u", sizeBytes: 2,
            modifiedAt: "u", matched: false, at: "2026-06-19T11:00:00Z"
        )

        let loaded = try #require(try db.fileStateForPath("/tmp/forel/a.txt"))
        #expect(loaded.lastProcessedAt == "2026-06-19T11:00:00Z")
        #expect(loaded.lastMatchedAt == "2026-06-19T10:00:00Z")
        #expect(loaded.contentFingerprint == "2:u")
    }

    // MARK: - Deletion

    @Test func deleteFileStateRemovesSingleRow() throws {
        let db = try makeDB()
        let folder = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/a.txt"))
        try db.upsertFileState(FileState(folderId: folder.id, path: "/tmp/forel/b.txt"))

        try db.deleteFileState(path: "/tmp/forel/a.txt")

        #expect(try db.fileStateForPath("/tmp/forel/a.txt") == nil)
        #expect(try db.fileStateForPath("/tmp/forel/b.txt") != nil)
    }

    @Test func deleteFileStatesClearsOnlyTargetFolder() throws {
        let db = try makeDB()
        let folderA = try insertedFolder(db)
        let folderB = try insertedFolder(db)
        try db.upsertFileState(FileState(folderId: folderA.id, path: "/tmp/a/x.txt"))
        try db.upsertFileState(FileState(folderId: folderB.id, path: "/tmp/b/y.txt"))

        try db.deleteFileStates(folderId: folderA.id)

        #expect(try db.listFileStates(folderId: folderA.id).isEmpty)
        #expect(try db.listFileStates(folderId: folderB.id).count == 1)
    }
}
