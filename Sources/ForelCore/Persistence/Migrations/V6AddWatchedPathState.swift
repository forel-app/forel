extension Database {
    func migrateV6AddWatchedPathState() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS watched_path_state (
                path        TEXT PRIMARY KEY,
                volume_id   INTEGER,
                file_id     INTEGER,
                fingerprint TEXT,
                updated_at  TEXT NOT NULL
            );
            """
        )
    }
}
