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
    func migrateV2AddActionHistory() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS action_history (
                id            TEXT PRIMARY KEY,
                batch_id      TEXT NOT NULL,
                rule_id       TEXT,
                rule_name     TEXT NOT NULL,
                action_kind   TEXT NOT NULL,
                original_path TEXT NOT NULL,
                result_path   TEXT NOT NULL,
                undo          TEXT NOT NULL,
                reversible    INTEGER NOT NULL DEFAULT 0,
                status        TEXT NOT NULL DEFAULT 'applied',
                message       TEXT,
                created_at    TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_action_history_batch ON action_history(batch_id);
            CREATE INDEX IF NOT EXISTS idx_action_history_created ON action_history(created_at);
            """
        )
    }
}
