import SwiftUI

struct QueryEditorView: View {
    @Bindable var tab: QueryTab
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore

    var body: some View {
        GraphQLTextEditor(text: $tab.query, schema: resolvedSchema)
    }

    private var resolvedSchema: GraphQLSchema? {
        let endpoint = tab.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return nil }
        let normalized = SchemaStore.normalizeEndpoint(endpoint)
        if case .loaded(let schema) = schemaStore.state(for: normalized) {
            return schema
        }
        return nil
    }
}
