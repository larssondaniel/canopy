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
            pillLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var pillLabel: some View {
        HStack(spacing: 4) {
            if let env = activeEnvironment {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(env.environmentColor.color)
                    .font(.system(size: 11, weight: .medium))
                Text(env.name.isEmpty ? "Untitled" : env.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            } else {
                Text("No Environment")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.quaternary)
        )
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
