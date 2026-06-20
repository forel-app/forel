extension Database {
    func migrateV4AddHistoryMessage() throws {
        if try tableHasColumn("action_history", "message") { return }
        try exec("ALTER TABLE action_history ADD COLUMN message TEXT;")
    }
}
