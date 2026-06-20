extension Database {
    func migrateV1AddRecursionDepth() throws {
        if try tableHasColumn("rules", "recursion_depth") { return }
        try exec("ALTER TABLE rules ADD COLUMN recursion_depth INTEGER NOT NULL DEFAULT 0;")
    }
}
