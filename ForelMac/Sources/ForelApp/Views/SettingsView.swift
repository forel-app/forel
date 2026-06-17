import SwiftUI
import ServiceManagement

private enum Theme: String, CaseIterable {
    case system, light, dark
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: UpdaterManager
    @State private var theme: Theme = .system
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }
                .onChange(of: theme) { _, newValue in
                    try? model.db.setSetting("theme", newValue.rawValue)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            model.errorMessage = "\(error)"
                        }
                    }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: automaticUpdatesBinding)
                Button("Check for Updates Now") { updater.checkForUpdates() }
            }

            Section("About") {
                Text("Forel")
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "alpha")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            let stored = (try? model.db.getSetting("theme")) ?? nil
            theme = Theme(rawValue: stored ?? "system") ?? .system
        }
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(get: { updater.automaticallyChecksForUpdates }, set: { updater.automaticallyChecksForUpdates = $0 })
    }
}
