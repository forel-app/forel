extension Database {
    func migrateV5AddFolderPriority() throws {
        if try tableHasColumn("watched_folders", "priority") { return }
        try exec("ALTER TABLE watched_folders ADD COLUMN priority INTEGER NOT NULL DEFAULT 0;")

        let select = try statement("SELECT id FROM watched_folders ORDER BY created_at")
        var ids: [String] = []
        while try select.step() {
            ids.append(select.columnText(0))
        }
        for (index, id) in ids.enumerated() {
            let update = try statement("UPDATE watched_folders SET priority=?1 WHERE id=?2")
            update.bind(1, Int64(index))
            update.bind(2, id)
            try update.runToCompletion()
        }
    }
}
