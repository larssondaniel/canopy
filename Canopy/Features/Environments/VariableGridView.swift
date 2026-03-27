import SwiftUI
import SwiftData

struct VariableGridView: View {
    @Binding var environments: [AppEnvironment]
    @State private var newKeyName = ""
    @State private var editingKey: String?

    /// All variable keys shared across environments, in stable order
    private var allKeys: [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for env in environments {
            for key in env.variables.keys.sorted() {
                if seen.insert(key).inserted {
                    keys.append(key)
                }
            }
        }
        return keys
    }

    var body: some View {
        VStack(spacing: 0) {
            if environments.isEmpty {
                ContentUnavailableView {
                    Label("No Environments", systemImage: "tray")
                } description: {
                    Text("Add an environment to start defining variables.")
                }
                .frame(maxHeight: .infinity)
            } else {
                gridContent
            }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    Text("Variable")
                        .fontWeight(.semibold)
                        .frame(width: 150, alignment: .leading)
                        .padding(8)

                    ForEach(environments) { env in
                        Text(env.name.isEmpty ? "Untitled" : env.name)
                            .fontWeight(.semibold)
                            .frame(minWidth: 180, alignment: .leading)
                            .padding(8)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Variable rows
                ForEach(allKeys, id: \.self) { key in
                    GridRow {
                        HStack {
                            Text(key)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                removeKey(key)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(8)

                        ForEach(environments) { env in
                            let binding = Binding<String>(
                                get: { env.variables[key] ?? "" },
                                set: { env.variables[key] = $0 }
                            )
                            TextField("Value", text: binding)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(minWidth: 180)
                                .padding(4)
                        }
                    }
                }

                Divider()

                // Add variable row
                GridRow {
                    HStack {
                        TextField("New variable name", text: $newKeyName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit {
                                addKey()
                            }
                        Button("Add") {
                            addKey()
                        }
                        .disabled(newKeyName.trimmingCharacters(in: .whitespaces).isEmpty || !isValidKeyName(newKeyName) || allKeys.contains(newKeyName.trimmingCharacters(in: .whitespaces)))
                    }
                    .frame(width: 150)
                    .padding(8)
                }
            }
        }
    }

    private func addKey() {
        let trimmed = newKeyName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isValidKeyName(trimmed), !allKeys.contains(trimmed) else { return }
        for env in environments {
            env.variables[trimmed] = ""
        }
        newKeyName = ""
    }

    private func removeKey(_ key: String) {
        for env in environments {
            env.variables.removeValue(forKey: key)
        }
    }

    private func isValidKeyName(_ name: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_]*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
