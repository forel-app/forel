import AppKit

/// Bundled brand assets: the full-colour Forel leaf app icon and the white
/// glyph used in the menu bar (`Resources/AppIcon.png`, `Resources/TrayIcon.png`
@MainActor
enum AppIcons {
    static let appIcon: NSImage? = loadImage("AppIcon")
    /// White-on-transparent leaf glyph, sized down for the menu bar.
    static let trayGlyph: NSImage? = loadImage("TrayIcon")

    private static func loadImage(_ name: String) -> NSImage? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Forel_ForelApp.bundle/Resources/\(name).png"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/\(name).png")
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) {
                return image
            }
        }
        return nil
    }
}
