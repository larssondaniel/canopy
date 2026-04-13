import SwiftUI
import SwiftData

struct EnvironmentPicker: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt) private var projects: [Project]

    private var project: Project? {
        projects.first
    }

    private var activeEnvironment: ProjectEnvironment? {
        project?.activeEnvironment
    }

    var body: some View {
        Menu {
            Button {
                setActiveEnvironment(nil)
            } label: {
                HStack {
                    Text("No Environment")
                    if project?.activeEnvironmentId == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            if let project, !project.environments.isEmpty {
                Divider()

                ForEach(project.environments.sorted(by: { $0.sortOrder < $1.sortOrder })) { env in
                    Button {
                        setActiveEnvironment(env.id)
                    } label: {
                        Label {
                            Text(env.name.isEmpty ? "Untitled" : env.name)
                        } icon: {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(env.environmentColor.color)
                        }
                    }
                }
            }

            Divider()

            Button("Manage Environments...") {
                appState.showEnvironments = true
            }
        } label: {
            if let env = activeEnvironment {
                Text(env.name.isEmpty ? "Untitled" : env.name)
            } else {
                Text("No Environment")
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 8)
    }

    private func setActiveEnvironment(_ environmentID: UUID?) {
        project?.activeEnvironmentId = environmentID
    }
}
