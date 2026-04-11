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
    private let client = GraphQLClient()

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
        .environment(\.runOperationAction, RunOperationAction { segment in
            run(segment: segment)
        })
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let tab = activeQueryTab {
                    if tab.isLoading {
                        Button { cancel() } label: {
                            Label("Cancel", systemImage: "stop.fill")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .keyboardShortcut(.escape, modifiers: [])
                    } else {
                        Button { run() } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(hasUnresolved)
                        .help(runButtonTooltip)
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                if let tab = activeQueryTab {
                    @Bindable var tab = tab
                    Menu {
                        ForEach(HTTPMethod.allCases, id: \.self) { method in
                            Button(method.rawValue) { tab.method = method }
                        }
                    } label: {
                        Text(tab.method.rawValue)
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            ToolbarItem(placement: .automatic) {
                if let tab = activeQueryTab {
                    @Bindable var tab = tab
                    TemplateTextField(
                        text: $tab.endpoint,
                        placeholder: "https://example.com/graphql",
                        activeEnvironment: activeEnvironment
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 200, idealWidth: 400, maxWidth: .infinity)
                }
            }

            ToolbarItem(placement: .automatic) {
                Text("⌘⏎")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
            }

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

    // MARK: - Unresolved Variable Validation

    private var hasUnresolved: Bool {
        activeQueryTab?.hasUnresolvedVariables(environment: activeEnvironment) ?? false
    }

    private var runButtonTooltip: String {
        if let names = activeQueryTab?.unresolvedVariableNames(environment: activeEnvironment), !names.isEmpty {
            return "Undefined variables: \(names.map { "{{\($0)}}" }.joined(separator: ", "))"
        }
        return "Send request (⌘⏎)"
    }

    // MARK: - Run / Cancel

    private func run(segment: OperationSegment? = nil) {
        guard let tab = activeQueryTab else { return }
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

            await client.send(tab: tab, environmentVariables: activeEnvironment?.variables, operationName: operationName)

            if tab.lastError == nil, tab.responseStatusCode != nil {
                let endpoint: String
                if let envVars = activeEnvironment?.variables {
                    endpoint = TemplateEngine.substitute(in: tab.endpoint, variables: envVars).resolvedText
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
