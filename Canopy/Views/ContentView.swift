import SwiftUI
import SwiftData

struct ContentView: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryTab.sortOrder) private var tabs: [QueryTab]
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]
    @Query private var activeStates: [ActiveEnvironmentState]
    @State private var astService = QueryASTService()

    private var activeEnvironment: AppEnvironment? {
        guard let activeID = activeStates.first?.activeEnvironmentID else { return nil }
        return environments.first { $0.id == activeID }
    }

    private var activeQueryTab: QueryTab? {
        guard let queryID = appState.selectedTab?.queryID else { return nil }
        return tabs.first { $0.id == queryID }
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(activeTab: activeQueryTab, astService: astService)
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
        .onChange(of: appState.selectedTab) { _, newTab in
            updateActiveEndpoint(for: newTab)
        }
        .onChange(of: activeStates.first?.activeEnvironmentID) { _, _ in
            updateActiveEndpoint(for: appState.selectedTab)
        }
    }

    @ViewBuilder
    private var contentForSelectedTab: some View {
        switch appState.selectedTab {
        case .query(let id):
            if let tab = tabs.first(where: { $0.id == id }) {
                QueryClientView(tab: tab, activeEnvironment: activeEnvironment, astService: astService)
            } else {
                welcomeView
            }
        case .environments:
            EnvironmentContentView()
        case nil:
            welcomeView
        }
    }

    private func updateActiveEndpoint(for tab: ContentTab?) {
        guard let queryID = tab?.queryID,
              let queryTab = tabs.first(where: { $0.id == queryID }) else {
            schemaStore.setActiveEndpoint(nil)
            return
        }
        let endpoint = queryTab.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            schemaStore.setActiveEndpoint(nil)
            return
        }

        let resolved: String
        if let envVars = activeEnvironment?.variables {
            resolved = TemplateEngine.substitute(in: endpoint, variables: envVars).resolvedText
        } else {
            resolved = endpoint
        }

        schemaStore.setActiveEndpoint(
            resolved,
            method: queryTab.method,
            auth: queryTab.authConfig.toAuthConfiguration(),
            headers: queryTab.headers
        )

        // Auto-load schema from cache (or fetch if needed) when endpoint becomes active
        schemaStore.fetchSchema(
            endpoint: resolved,
            method: queryTab.method,
            auth: queryTab.authConfig.toAuthConfiguration(),
            headers: queryTab.headers
        )
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
