import SwiftUI
import ForelCore

struct RuleListView: View {
    @EnvironmentObject var model: AppModel
    @Binding var showHistory: Bool
    @State private var editingRule: Rule?
    @State private var previewResult: PreviewResult?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.rules, id: \.id) { rule in
                    RuleRow(rule: rule, onEdit: { editingRule = rule })
                }
                .onMove { indices, newOffset in
                    var ids = model.rules.map(\.id)
                    ids.move(fromOffsets: indices, toOffset: newOffset)
                    model.reorderRules(ids)
                }
            }

            Divider()

            HStack {
                Button("New Rule") {
                    guard let folderId = model.selectedFolderId else { return }
                    editingRule = Rule(folderId: folderId, name: "New Rule")
                }
                Button("Run Now") { model.runNow() }
                    .disabled(model.selectedFolderId == nil)
                Button("Preview") { previewResult = model.preview() }
                    .disabled(model.selectedFolderId == nil)
                Spacer()
                Button("History") {
                    model.reloadHistory()
                    showHistory = true
                }
            }
            .padding(8)
        }
        .navigationTitle("Rules")
        .sheet(item: $editingRule) { rule in
            RuleEditorView(rule: rule) { saved in
                model.saveRule(saved)
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
        .sheet(item: $previewResult) { result in
            PreviewSheet(result: result) { previewResult = nil }
        }
    }
}

private struct RuleRow: View {
    @EnvironmentObject var model: AppModel
    let rule: Rule
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: enabledBinding).labelsHidden()
            VStack(alignment: .leading) {
                Text(rule.name)
                Text("\(rule.conditions.count) condition(s), \(rule.actions.count) action(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", action: onEdit)
            Button(role: .destructive) { model.deleteRule(rule) } label: {
                Image(systemName: "trash")
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { rule.enabled }, set: { model.toggleRule(rule, enabled: $0) })
    }
}

extension PreviewResult: Identifiable {
    public var id: Int { filesScanned.hashValue ^ matches.count.hashValue }
}

extension Rule: Identifiable {}

private struct PreviewSheet: View {
    let result: PreviewResult
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Scanned \(result.filesScanned) file(s), \(result.matches.count) would change")
                .font(.headline)
                .padding(.bottom, 8)
            List(result.matches, id: \.path) { match in
                VStack(alignment: .leading) {
                    Text(match.name).bold()
                    ForEach(match.rules, id: \.ruleId) { rulePreview in
                        Text(rulePreview.ruleName).font(.caption).foregroundStyle(.secondary)
                        ForEach(rulePreview.actions, id: \.self) { action in
                            Text("• \(action)").font(.caption2)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close", action: onClose)
            }
        }
        .padding()
        .frame(width: 480, height: 420)
    }
}
