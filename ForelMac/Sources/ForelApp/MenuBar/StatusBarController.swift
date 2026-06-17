import AppKit
import ForelCore

/// Menu-bar item: Forel glyph with a green/red status dot, plus the dropdown
/// menu (Open Forel, watching status, Start/Stop Watching, Check for Updates,
/// Quit). Mirrors `tray.rs`.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private weak var window: NSWindow?
    private let checkForUpdates: () -> Void

    init(model: AppModel, window: NSWindow?, checkForUpdates: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.model = model
        self.window = window
        self.checkForUpdates = checkForUpdates
        super.init()
        rebuild()
    }

    func rebuild() {
        if let button = statusItem.button {
            button.image = Self.glyph(paused: model.paused)
            button.image?.isTemplate = false
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Open Forel", action: #selector(openForel), keyEquivalent: "").with(target: self))
        menu.addItem(.separator())

        let statusLabel = model.paused ? "File watching is stopped" : "File watching is running"
        let statusItemEntry = NSMenuItem(title: statusLabel, action: nil, keyEquivalent: "")
        statusItemEntry.isEnabled = false
        statusItemEntry.image = Self.dot(paused: model.paused)
        menu.addItem(statusItemEntry)

        let toggleLabel = model.paused ? "Start Watching" : "Stop Watching"
        menu.addItem(NSMenuItem(title: toggleLabel, action: #selector(toggleWatching), keyEquivalent: "").with(target: self))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkUpdates), keyEquivalent: "").with(target: self))
        menu.addItem(NSMenuItem(title: "Quit Forel", action: #selector(quit), keyEquivalent: "q").with(target: self))

        return menu
    }

    @objc private func openForel() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleWatching() {
        model.togglePaused()
        rebuild()
    }

    @objc private func checkUpdates() {
        openForel()
        checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Status-dot-only image used inline in the disabled status menu row.
    private static func dot(paused: Bool, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        (paused ? NSColor.systemRed : NSColor.systemGreen).setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        return image
    }

    /// Menu bar glyph with a colour dot composited in the bottom-right corner.
    private static func glyph(paused: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.labelColor.setFill()
        let bodyRect = NSRect(x: 2, y: 2, width: size - 4, height: size - 4)
        NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3).fill()
        image.unlockFocus()

        let dotSize: CGFloat = size / 3
        let dotImage = dot(paused: paused, size: dotSize)
        image.lockFocus()
        dotImage.draw(at: NSPoint(x: size - dotSize - 1, y: 0), from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        return image
    }
}

private extension NSMenuItem {
    func with(target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
