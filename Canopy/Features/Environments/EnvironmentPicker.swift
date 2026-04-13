import SwiftUI

struct EnvironmentPicker: View {
    @SwiftUI.Environment(ProjectWindowState.self) private var windowState
    var project: Project

    private var activeEnvironment: ProjectEnvironment? {
        project.activeEnvironment
    }

    var body: some View {
        @Bindable var windowState = windowState

        Menu {
            Button {
                setActiveEnvironment(nil)
            } label: {
                HStack {
                    Text("Default")
                    if project.activeEnvironmentId == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !project.environments.isEmpty {
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
                windowState.showEnvironments = true
            }
        } label: {
            if let env = activeEnvironment {
                Label {
                    Text(env.name.isEmpty ? "Untitled" : env.name)
                } icon: {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(env.environmentColor.color)
                }
            } else {
                Text("Default")
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 8)
    }

    private func setActiveEnvironment(_ environmentID: UUID?) {
        project.activeEnvironmentId = environmentID
    }
}
