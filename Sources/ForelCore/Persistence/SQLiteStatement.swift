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

import SQLite3
import Foundation

public struct SQLiteError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Thin wrapper around a single prepared SQLite statement. Indices are 1-based
/// for binding (matching sqlite3_bind_*) and 0-based for reading columns
/// (matching sqlite3_column_*), same as the C API.
final class SQLiteStatement {
    private let handle: OpaquePointer
    private var stmt: OpaquePointer?

    init(_ handle: OpaquePointer, _ sql: String) throws {
        self.handle = handle
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError(String(cString: sqlite3_errmsg(handle)))
        }
    }

    deinit { sqlite3_finalize(stmt) }

    func bind(_ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    func bind(_ index: Int32, _ value: String?) {
        if let value { bind(index, value) } else { sqlite3_bind_null(stmt, index) }
    }

    func bind(_ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    func bind(_ index: Int32, _ value: Int64?) {
        if let value { bind(index, value) } else { sqlite3_bind_null(stmt, index) }
    }

    func bind(_ index: Int32, bool value: Bool) {
        sqlite3_bind_int64(stmt, index, value ? 1 : 0)
    }

    /// Advances to the next row. Returns false when there are no more rows.
    @discardableResult
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SQLiteError(String(cString: sqlite3_errmsg(handle)))
    }

    func runToCompletion() throws {
        while try step() {}
    }

    func columnText(_ index: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cstr)
    }

    func columnTextOrNil(_ index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return columnText(index)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    func columnInt64OrNil(_ index: Int32) -> Int64? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return columnInt64(index)
    }

    func columnBool(_ index: Int32) -> Bool {
        columnInt64(index) != 0
    }
}

// sqlite3_bind_text/blob need a destructor; SQLITE_TRANSIENT tells SQLite to
// copy the buffer, since `value` is a temporary Swift String/CString.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
