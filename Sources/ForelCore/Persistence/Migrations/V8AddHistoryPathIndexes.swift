extension Database {
    func migrateV8AddHistoryPathIndexes() throws {
        try exec(
            """
            CREATE INDEX IF NOT EXISTS idx_action_history_original_path ON action_history(original_path);
            CREATE INDEX IF NOT EXISTS idx_action_history_result_path ON action_history(result_path);
            """
        )
    }
}
