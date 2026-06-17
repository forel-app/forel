import SwiftUI
import ForelCore

struct RuleEditorView: View {
    @State private var rule: Rule
    let onSave: (Rule) -> Void
    let onCancel: () -> Void

    init(rule: Rule, onSave: @escaping (Rule) -> Void, onCancel: @escaping () -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rule.name.isEmpty ? "New Rule" : "Edit Rule").font(.title2)

            TextField("Name", text: $rule.name)

            Picker("Scope", selection: scopeBinding) {
                Text("This folder only").tag(0 as Int64?)
                Text("1 level deep").tag(1 as Int64?)
                Text("All subfolders").tag(nil as Int64?)
            }

            Picker("Match", selection: $rule.conditionMatch) {
                Text("All conditions").tag(ConditionMatch.all)
                Text("Any condition").tag(ConditionMatch.any)
            }
            .pickerStyle(.segmented)

            GroupBox("Conditions") {
                VStack(alignment: .leading) {
                    ForEach($rule.conditions, id: \.id) { $condition in
                        ConditionRow(condition: $condition) {
                            rule.conditions.removeAll { $0.id == condition.id }
                        }
                    }
                    Button("Add Condition") {
                        rule.conditions.append(Condition(ruleId: rule.id, kind: .name, operator: .contains, value: ""))
                    }
                }
            }

            GroupBox("Actions") {
                VStack(alignment: .leading) {
                    ForEach($rule.actions, id: \.id) { $action in
                        ActionRow(action: $action) {
                            rule.actions.removeAll { $0.id == action.id }
                        }
                    }
                    Button("Add Action") {
                        rule.actions.append(Action(ruleId: rule.id, kind: .moveToFolder, params: .object(["destination": .string("")]), position: Int64(rule.actions.count)))
                    }
                }
            }

            Toggle("Enabled", isOn: $rule.enabled)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { onSave(rule) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 560, height: 560)
    }

    private var scopeBinding: Binding<Int64?> {
        Binding(get: { rule.recursionDepth }, set: { rule.recursionDepth = $0 })
    }
}

private struct ConditionRow: View {
    @Binding var condition: Condition
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Picker("", selection: $condition.kind) {
                ForEach(ConditionEditorLabels.kinds, id: \.0) { kind, label in
                    Text(label).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Picker("", selection: $condition.operator) {
                ForEach(ConditionEditorLabels.operators, id: \.0) { op, label in
                    Text(label).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            TextField("Value", text: $condition.value)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
        }
    }
}

private struct ActionRow: View {
    @Binding var action: Action
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("", selection: kindBinding) {
                    ForEach(ConditionEditorLabels.actionKinds, id: \.0) { kind, label in
                        Text(label).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
            }

            switch action.kind {
            case .moveToFolder, .copyToFolder:
                TextField("Destination folder", text: paramBinding("destination"))
            case .rename:
                TextField("Pattern, e.g. {name}-{current_date}.{extension}", text: paramBinding("pattern"))
            case .addTag, .removeTag:
                TextField("Tag", text: paramBinding("tag"))
            case .setColorLabel:
                TextField("Color (red, orange, yellow, green, blue, purple, gray)", text: paramBinding("color"))
            case .runScript:
                TextField("Bash script (file path in $FOREL_FILE)", text: paramBinding("script"))
            case .moveToTrash, .delete:
                Text("No parameters").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { action.kind },
            set: { newKind in
                action = Action(id: action.id, ruleId: action.ruleId, kind: newKind, params: .object([:]), position: action.position)
            }
        )
    }

    private func paramBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { action.params[key]?.stringValue ?? "" },
            set: { newValue in
                var dict: [String: JSONValue] = [:]
                if case .object(let existing) = action.params { dict = existing }
                dict[key] = .string(newValue)
                action.params = .object(dict)
            }
        )
    }
}

enum ConditionEditorLabels {
    static let kinds: [(ConditionKind, String)] = [
        (.name, "Name"), (.extension_, "Extension"), (.kind, "Kind"), (.sizeBytes, "Size"),
        (.tags, "Tags"), (.colorLabel, "Color label"), (.contents, "Contents"),
        (.createdAt, "Date created"), (.dateModified, "Date modified"), (.dateAdded, "Date added"),
    ]

    static let operators: [(Operator, String)] = [
        (.is, "is"), (.isNot, "is not"), (.contains, "contains"), (.doesNotContain, "does not contain"),
        (.startsWith, "starts with"), (.endsWith, "ends with"), (.matchesRegex, "matches regex"),
        (.greaterThan, "greater than"), (.lessThan, "less than"), (.before, "is before"),
        (.after, "is after"), (.olderThan, "is older than"), (.withinLast, "is within the last"),
    ]

    static let actionKinds: [(ActionKind, String)] = [
        (.moveToFolder, "Move to folder"), (.copyToFolder, "Copy to folder"), (.rename, "Rename"),
        (.moveToTrash, "Move to Trash"), (.delete, "Delete"), (.addTag, "Add tag"),
        (.removeTag, "Remove tag"), (.setColorLabel, "Set color label"), (.runScript, "Run script"),
    ]
}
