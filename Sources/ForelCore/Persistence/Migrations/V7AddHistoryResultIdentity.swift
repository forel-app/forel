extension Database {
    func migrateV7AddHistoryResultIdentity() throws {
        if !(try tableHasColumn("action_history", "result_volume_id")) {
            try exec("ALTER TABLE action_history ADD COLUMN result_volume_id INTEGER;")
        }
        if !(try tableHasColumn("action_history", "result_file_id")) {
            try exec("ALTER TABLE action_history ADD COLUMN result_file_id INTEGER;")
        }
    }
}
