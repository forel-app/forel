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

import Testing
@testable import ForelCore

@Suite struct SystemFileFilterTests {
    @Test func excludesKnownNoisySystemFiles() {
        #expect(SystemFileFilter.isExcluded(".DS_Store"))
        #expect(SystemFileFilter.isExcluded("._report.pdf")) // AppleDouble resource fork
        #expect(SystemFileFilter.isExcluded("~$budget.docx")) // Office lock file
    }

    @Test func doesNotExcludeRegularFiles() {
        #expect(!SystemFileFilter.isExcluded("report.pdf"))
        #expect(!SystemFileFilter.isExcluded("budget.docx"))
        #expect(!SystemFileFilter.isExcluded("invoice_march_2026.pdf"))
    }
}
