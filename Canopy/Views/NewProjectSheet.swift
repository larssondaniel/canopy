import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var onCreated: (UUID) -> Void

    @State private var name = ""
    @State private var endpointURL = ""
    @State private var introspectionState: IntrospectionState = .idle

    private enum IntrospectionState {
        case idle
        case loading
        case success
        case failed(String)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !endpointURL.trimmingCharacters(in: .whitespaces).isEmpty
        && hasValidScheme
    }

    private var hasValidScheme: Bool {
        guard let url = URL(string: endpointURL.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title2.bold())

            TextField("Project Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Endpoint URL", text: $endpointURL)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 6) {
                    switch introspectionState {
                    case .idle:
                        EmptyView()
                    case .loading:
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking endpoint...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Schema found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 16)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Create") {
                    createProject()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: endpointURL) { _, newValue in
            tryIntrospection(endpoint: newValue)
        }
    }

    private func createProject() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = endpointURL.trimmingCharacters(in: .whitespaces)

        let project = Project(
            name: trimmedName,
            endpointPattern: "{{host}}",
            defaultVariables: [Variable(key: "host", value: trimmedURL)]
        )
        modelContext.insert(project)

        let tab = QueryTab()
        tab.endpoint = "{{host}}"
        tab.project = project
        modelContext.insert(tab)

        onCreated(project.id)
        dismiss()
    }

    private func tryIntrospection(endpoint: String) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            introspectionState = .idle
            return
        }

        introspectionState = .loading
        Task {
            let client = IntrospectionClient()
            do {
                _ = try await client.fetchSchema(url: url, method: .post, auth: .none, headers: [])
                introspectionState = .success
            } catch {
                introspectionState = .failed("Could not reach endpoint")
            }
        }
    }
}
