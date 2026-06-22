// Forel - A native macOS file-automation app
// Copyright (C) 2026  Lab421
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
