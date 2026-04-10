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
        tabs.first
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar(activeTab: activeQueryTab, astService: astService)
        } detail: {
            if let tab = activeQueryTab {
                QueryClientView(tab: tab, activeEnvironment: activeEnvironment, astService: astService)
            } else {
                ContentUnavailableView("No Query", systemImage: "arrow.right.circle", description: Text("Loading..."))
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EnvironmentPicker()
            }
        }
        .sheet(isPresented: $appState.showEnvironments) {
            EnvironmentContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .onAppear {
            appState.modelContext = modelContext
            _ = appState.ensureQueryTab()
        }
        .onChange(of: activeQueryTab?.endpoint) { _, _ in
            updateActiveEndpoint()
        }
        .onChange(of: activeStates.first?.activeEnvironmentID) { _, _ in
            updateActiveEndpoint()
        }
        .onAppear {
            updateActiveEndpoint()
        }
    }

    private func updateActiveEndpoint() {
        guard let queryTab = activeQueryTab else {
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

        schemaStore.fetchSchema(
            endpoint: resolved,
            method: queryTab.method,
            auth: queryTab.authConfig.toAuthConfiguration(),
            headers: queryTab.headers
        )
    }
}
