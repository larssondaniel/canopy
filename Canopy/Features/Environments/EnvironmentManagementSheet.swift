import SwiftUI
import SwiftData

struct EnvironmentManagementSheet: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]

    @State private var editingNameID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Environments")
                    .font(.headline)
                Spacer()
                Button("Add Environment") {
                    addEnvironment()
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Environment tabs
            if !environments.isEmpty {
                HStack(spacing: 4) {
                    ForEach(environments) { env in
                        environmentTab(for: env)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
            }

            // Variable grid
            VariableGridView(environments: .constant(environments))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    @ViewBuilder
    private func environmentTab(for env: AppEnvironment) -> some View {
        HStack(spacing: 4) {
            if editingNameID == env.id {
                TextField("Name", text: Binding(
                    get: { env.name },
                    set: { env.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onSubmit {
                    editingNameID = nil
                }
            } else {
                Text(env.name.isEmpty ? "Untitled" : env.name)
                    .onTapGesture(count: 2) {
                        editingNameID = env.id
                    }
            }

            Button {
                deleteEnvironment(env)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func addEnvironment() {
        // Collect existing keys
        let existingKeys: [String] = environments.first?.variables.keys.sorted() ?? []
        var variables: [String: String] = [:]
        for key in existingKeys {
            variables[key] = ""
        }

        let env = AppEnvironment(
            name: "New Environment",
            variables: variables,
            sortOrder: (environments.last?.sortOrder ?? -1) + 1
        )
        modelContext.insert(env)
        editingNameID = env.id
    }

    private func deleteEnvironment(_ env: AppEnvironment) {
        modelContext.delete(env)
    }
}
