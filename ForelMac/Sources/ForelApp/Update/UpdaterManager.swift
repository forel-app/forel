import Sparkle
import Foundation

/// Thin wrapper around Sparkle's standard updater, driven by a GitHub
/// Releases appcast. Replaces the Tauri updater plugin.
@MainActor
final class UpdaterManager: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
