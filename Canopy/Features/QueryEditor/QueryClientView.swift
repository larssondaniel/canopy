import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var astService: QueryASTService
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore
    private let client = GraphQLClient()

    var body: some View {
        HSplitView {
            RequestPane(tab: tab, activeEnvironment: activeEnvironment, onRun: { run() }, onCancel: cancel)
                .frame(minWidth: 300)
            ResponsePane(tab: tab)
                .frame(minWidth: 300)
        }
        .environment(\.runOperationAction, RunOperationAction { segment in
            run(segment: segment)
        })
    }

    private func run(segment: OperationSegment? = nil) {
        tab.currentTask?.cancel()
        tab.currentTask = Task {
            // Determine operationName for multi-operation documents
            let operationName: String?
            if let doc = astService.currentDocument,
               doc.definitions.count > 1 {
                // Multiple operations — use the specified segment or the active one
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

            // After successful query, update the active endpoint and auto-fetch schema
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
        tab.currentTask?.cancel()
        tab.isLoading = false
    }
}
