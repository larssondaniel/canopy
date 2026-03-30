import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore
    private let client = GraphQLClient()

    var body: some View {
        HSplitView {
            RequestPane(tab: tab, activeEnvironment: activeEnvironment, onRun: run, onCancel: cancel)
                .frame(minWidth: 300)
            ResponsePane(tab: tab)
                .frame(minWidth: 300)
        }
    }

    private func run() {
        tab.currentTask?.cancel()
        tab.currentTask = Task {
            await client.send(tab: tab, environmentVariables: activeEnvironment?.variables)

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
                // fetchSchema skips if already loaded, normalizes internally
                schemaStore.fetchSchema(endpoint: endpoint)
            }
        }
    }

    private func cancel() {
        tab.currentTask?.cancel()
        tab.isLoading = false
    }
}
