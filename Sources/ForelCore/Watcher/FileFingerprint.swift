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

import Darwin
import Foundation

/// Stable on-disk identity for a file: which volume it's on and its inode
/// number. Used only by `WatcherCoordinator` to tell whether a path still
/// refers to the same file it last evaluated.
struct FileIdentity: Equatable {
    let volumeId: Int64
    let fileId: Int64
}

enum FileFingerprint {
    /// Cheap content fingerprint based on size and modification time —
    /// enough to detect "this file changed since we last looked" without
    /// hashing file contents.
    static func current(_ path: String) -> String? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return "\(st.st_size)-\(st.st_mtimespec.tv_sec)-\(st.st_mtimespec.tv_nsec)"
    }

    static func identity(_ path: String) -> FileIdentity? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return FileIdentity(volumeId: Int64(st.st_dev), fileId: Int64(st.st_ino))
    }
}
