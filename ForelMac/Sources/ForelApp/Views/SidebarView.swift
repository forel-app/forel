import SwiftUI
import ForelCore
import AppKit

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: selectionBinding) {
            Section("Watched Folders") {
                ForEach(model.folders, id: \.id) { folder in
                    HStack {
                        Toggle("", isOn: enabledBinding(folder)).labelsHidden()
                        Text((folder.path as NSString).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                    }
                    .tag(folder.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) { model.removeFolder(folder) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: addFolder) {
                    Label("Add Folder", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Forel")
    }

    private var selectionBinding: Binding<String?> {
        Binding(get: { model.selectedFolderId }, set: { model.selectedFolderId = $0; model.reloadRules() })
    }

    private func enabledBinding(_ folder: WatchedFolder) -> Binding<Bool> {
        Binding(get: { folder.enabled }, set: { model.toggleFolder(folder, enabled: $0) })
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.addFolder(path: url.path)
        }
    }
}
