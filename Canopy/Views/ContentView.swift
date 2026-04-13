import SwiftUI
import SwiftData

struct ContentView: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryTab.sortOrder) private var tabs: [QueryTab]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @State private var astService = QueryASTService()
    private let client = GraphQLClient()

    private var project: Project? {
        projects.first
    }

    private var resolvedVariables: [String: String] {
        project?.resolvedVariables() ?? [:]
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
                QueryClientView(tab: tab, resolvedVariables: resolvedVariables, astService: astService)
            } else {
                ContentUnavailableView("No Query", systemImage: "arrow.right.circle", description: Text("Loading..."))
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        .navigationTitle(project?.name.isEmpty == false ? project!.name : "Untitled Project")
        .toolbarTitleDisplayMode(.inline)
        .environment(\.runOperationAction, RunOperationAction { segment in
            run(segment: segment)
        })
        .toolbar {
            ToolbarItem(placement: .navigation) {
                RunCancelButton(
                    tab: activeQueryTab,
                    resolvedVariables: resolvedVariables,
                    onRun: { run() },
                    onCancel: cancel
                )
            }

            ToolbarItem(placement: .automatic) {
                if #available(macOS 26.0, *) {
                    EnvironmentPicker()
                        .glassEffect(.identity)
                } else {
                    EnvironmentPicker()
                }
            }
        }
        .sheet(isPresented: $appState.showEnvironments) {
            EnvironmentContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .onAppear {
            appState.modelContext = modelContext
            _ = appState.ensureQueryTab()
            _ = appState.ensureProject()
        }
        .onChange(of: activeQueryTab?.endpoint) { _, _ in
            updateActiveEndpoint()
        }
        .onChange(of: project?.activeEnvironmentId) { _, _ in
            updateActiveEndpoint()
        }
        .onAppear {
            updateActiveEndpoint()
        }
    }

    // MARK: - Run / Cancel

    private func run(segment: OperationSegment? = nil) {
        guard let tab = activeQueryTab else { return }
        let vars = resolvedVariables
        tab.currentTask?.cancel()
        tab.currentTask = Task {
            let operationName: String?
            if let doc = astService.currentDocument,
               doc.definitions.count > 1 {
                let targetSegment = segment ?? astService.activeSegment ?? .queries
                switch targetSegment {
                case .queries: operationName = "Query"
                case .mutations: operationName = "Mutation"
                case .subscriptions: operationName = "Subscription"
                }
            } else {
                operationName = nil
            }

            await client.send(tab: tab, environmentVariables: vars.isEmpty ? nil : vars, operationName: operationName)

            if tab.lastError == nil, tab.responseStatusCode != nil {
                let endpoint: String
                if !vars.isEmpty {
                    endpoint = TemplateEngine.substitute(in: tab.endpoint, variables: vars).resolvedText
                } else {
                    endpoint = tab.endpoint
                }

                schemaStore.setActiveEndpoint(
                    endpoint,
                    method: tab.method,
                    auth: tab.authConfig.toAuthConfiguration(),
                    headers: tab.headers
                )
                schemaStore.fetchSchema(endpoint: endpoint)
            }
        }
    }

    private func cancel() {
        guard let tab = activeQueryTab else { return }
        tab.currentTask?.cancel()
        tab.isLoading = false
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

        let vars = resolvedVariables
        let resolved: String
        if !vars.isEmpty {
            resolved = TemplateEngine.substitute(in: endpoint, variables: vars).resolvedText
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
