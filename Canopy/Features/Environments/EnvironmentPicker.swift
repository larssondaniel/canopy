import SwiftUI
import SwiftData

struct EnvironmentPicker: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]
    @Query private var activeStates: [ActiveEnvironmentState]

    private var activeState: ActiveEnvironmentState? {
        activeStates.first
    }

    private var activeEnvironment: AppEnvironment? {
        guard let activeID = activeState?.activeEnvironmentID else { return nil }
        return environments.first { $0.id == activeID }
    }

    var body: some View {
        Menu {
            Button {
                setActiveEnvironment(nil)
            } label: {
                HStack {
                    Text("No Environment")
                    if activeState?.activeEnvironmentID == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !environments.isEmpty {
                Divider()

                ForEach(environments) { env in
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
        let state: ActiveEnvironmentState
        if let existing = activeStates.first {
            state = existing
        } else {
            state = ActiveEnvironmentState()
            modelContext.insert(state)
        }
        state.activeEnvironmentID = environmentID
    }
}
