extension Database {
    func migrateV3AddAppSettings() throws {
        try exec("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);")
    }
}
