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
    func migrateV7AddHistoryResultIdentity() throws {
        if !(try tableHasColumn("action_history", "result_volume_id")) {
            try exec("ALTER TABLE action_history ADD COLUMN result_volume_id INTEGER;")
        }
        if !(try tableHasColumn("action_history", "result_file_id")) {
            try exec("ALTER TABLE action_history ADD COLUMN result_file_id INTEGER;")
        }
    }
}
