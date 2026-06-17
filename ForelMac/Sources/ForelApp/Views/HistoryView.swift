import SwiftUI
import ForelCore

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @Binding var showHistory: Bool

    private var batches: [(id: String, entries: [HistoryEntry])] {
        let grouped = Dictionary(grouping: model.history, by: \.batchId)
        return grouped
            .map { (id: $0.key, entries: $0.value) }
            .sorted { ($0.entries.first?.createdAt ?? "") > ($1.entries.first?.createdAt ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(batches, id: \.id) { batch in
                    Section(batch.entries.first?.createdAt ?? batch.id) {
                        ForEach(batch.entries, id: \.id) { entry in
                            HistoryRow(entry: entry)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Back") { showHistory = false }
                Spacer()
                Button("Clear History", role: .destructive) {
                    try? model.db.clearHistory()
                    model.reloadHistory()
                }
            }
            .padding(8)
        }
        .navigationTitle("History")
        .onAppear { model.reloadHistory() }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var model: AppModel
    let entry: HistoryEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(entry.ruleName): \(entry.actionKind.rawValue)")
                Text("\((entry.originalPath as NSString).lastPathComponent) → \((entry.resultPath as NSString).lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.status == .undone {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            } else if entry.reversible {
                Button("Undo") { model.undo(entry) }
            }
        }
    }
}
