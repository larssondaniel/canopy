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
        NavigationSplitView {
            Sidebar()
        } detail: {
            VStack(spacing: 0) {
                // Tab bar — shown when 2+ tabs are open
                if appState.openTabs.count >= 2 {
                    TabBarView()
                }

                // Content area — routes based on selected tab type
                contentForSelectedTab
            }
            .toolbar {
                // '+' button in toolbar when tab bar is hidden (0-1 tabs)
                if appState.openTabs.count < 2 {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            appState.addTab()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("New Tab")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    EnvironmentPicker()
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        .onAppear {
            appState.modelContext = modelContext
            appState.initializeTabs(from: tabs)
        }
    }

    @ViewBuilder
    private var contentForSelectedTab: some View {
        switch appState.selectedTab {
        case .query(let id):
            if let tab = tabs.first(where: { $0.id == id }) {
                QueryClientView(tab: tab, activeEnvironment: activeEnvironment)
            } else {
                welcomeView
            }
        case .environments:
            EnvironmentContentView()
        case nil:
            welcomeView
        }
    }

    @ViewBuilder
    private var welcomeView: some View {
        VStack(spacing: 12) {
            Text("Canopy")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("A native GraphQL client for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("New Tab") {
                appState.addTab()
            }
            .controlSize(.large)
            Text("or press \(Image(systemName: "command")) T")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
