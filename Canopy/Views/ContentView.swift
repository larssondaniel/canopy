import SwiftUI
import SwiftData

struct ContentView: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryTab.sortOrder) private var tabs: [QueryTab]
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]
    @Query private var activeStates: [ActiveEnvironmentState]

    private var activeEnvironment: AppEnvironment? {
        guard let activeID = activeStates.first?.activeEnvironmentID else { return nil }
        return environments.first { $0.id == activeID }
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar()
        } detail: {
            if let selectedTab = appState.selectedTab,
               let tab = tabs.first(where: { $0.id == selectedTab }) {
                QueryClientView(tab: tab, activeEnvironment: activeEnvironment)
            } else {
                VStack(spacing: 12) {
                    Text("Canopy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("A native GraphQL client for macOS")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Press \(Image(systemName: "command")) T to create a new query tab")
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EnvironmentPicker()
            }
        }
        .onAppear {
            appState.modelContext = modelContext
        }
    }
}
