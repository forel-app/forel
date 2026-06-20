extension Database {
    typealias Migration = (version: Int64, apply: @Sendable (Database) throws -> Void)

    static let migrations: [Migration] = [
        (1, { try $0.migrateV1AddRecursionDepth() }),
        (2, { try $0.migrateV2AddActionHistory() }),
        (3, { try $0.migrateV3AddAppSettings() }),
        (4, { try $0.migrateV4AddHistoryMessage() }),
        (5, { try $0.migrateV5AddFolderPriority() }),
        (6, { try $0.migrateV6AddWatchedPathState() }),
        (7, { try $0.migrateV7AddHistoryResultIdentity() }),
        (8, { try $0.migrateV8AddHistoryPathIndexes() }),
    ]

    func runMigrations() throws {
        let version = try userVersion()
        if version > Self.currentSchemaVersion {
            throw SQLiteError("database schema version \(version) is newer than supported \(Self.currentSchemaVersion)")
        }

        let migrations = try Self.validatedMigrations()
        for migration in migrations where version < migration.version {
            try runMigration(migration.version) {
                try migration.apply(self)
            }
        }
    }

    private func runMigration(_ version: Int64, _ apply: () throws -> Void) throws {
        try transaction {
            try apply()
            try setUserVersion(version)
        }
    }

    private static func validatedMigrations() throws -> [Migration] {
        let sorted = migrations.sorted { $0.version < $1.version }
        let versions = sorted.map(\.version)
        let expected = Array(Int64(1)...currentSchemaVersion)
        guard versions == expected else {
            throw SQLiteError("database migrations must cover versions 1...\(currentSchemaVersion) exactly")
        }
        return sorted
    }
}
