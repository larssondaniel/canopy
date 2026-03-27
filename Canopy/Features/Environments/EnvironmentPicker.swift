import SwiftUI
import SwiftData

struct EnvironmentPicker: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]
    @Query private var activeStates: [ActiveEnvironmentState]

    @State private var showManagementSheet = false

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
                        HStack {
                            Text(env.name.isEmpty ? "Untitled" : env.name)
                            if activeState?.activeEnvironmentID == env.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Manage Environments...") {
                showManagementSheet = true
            }
        } label: {
            Label {
                Text(activeEnvironment?.name ?? "No Environment")
            } icon: {
                Image(systemName: "globe")
            }
        }
        .sheet(isPresented: $showManagementSheet) {
            EnvironmentManagementSheet()
        }
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
