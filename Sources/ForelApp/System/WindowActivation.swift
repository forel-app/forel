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

import AppKit
import SwiftUI

@MainActor
enum WindowActivation {
    static func activate(_ window: NSWindow?, showsDockIcon: Bool = true) {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate()
        NSRunningApplication.current.activate(options: activationOptions)
    }

    private static var activationOptions: NSApplication.ActivationOptions {
        // rawValue keeps compatibility with the legacy "ignore other apps"
        // bit without referencing the deprecated symbol directly.
        NSApplication.ActivationOptions(rawValue: 1 | 2)
    }
}

struct WindowActivationBridge: NSViewRepresentable {
    let showsDockIcon: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            WindowActivation.activate(view.window, showsDockIcon: showsDockIcon)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            WindowActivation.activate(nsView.window, showsDockIcon: showsDockIcon)
        }
    }
}
