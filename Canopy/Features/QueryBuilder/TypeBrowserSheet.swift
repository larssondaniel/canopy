import SwiftUI

/// Type catalog browser presented as a sheet from the explorer toolbar.
/// Replaces the Schema tab with on-demand type browsing.
struct TypeBrowserSheet: View {
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore
    @SwiftUI.Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var expandedSections: Set<String> = []
    @State private var expandedTypes: Set<String> = []
    @State private var selectedTypeName: String?

    var body: some View {
        NavigationStack {
            Group {
                if let endpoint = schemaStore.activeEndpoint,
                   case .loaded(let schema) = schemaStore.state(for: endpoint) {
                    typeBrowser(schema: schema)
                } else {
                    ContentUnavailableView(
                        "No Schema",
                        systemImage: "doc.text",
                        description: Text("Load a schema to browse types.")
                    )
                }
            }
            .navigationTitle("Browse Types")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter types and fields")
        .frame(minWidth: 400, minHeight: 500)
    }

    @ViewBuilder
    private func typeBrowser(schema: GraphQLSchema) -> some View {
        let rootTypeNames: Set<String> = Set(
            [schema.queryTypeName, schema.mutationTypeName, schema.subscriptionTypeName].compactMap { $0 }
        )

        ScrollViewReader { proxy in
            List {
                ForEach(GraphQLTypeKind.topLevelKinds, id: \.self) { kind in
                    if let types = schema.sortedTypesByKind[kind]?.filter({
                        !rootTypeNames.contains($0.name)
                    }), !types.isEmpty {
                        let filtered = filteredTypes(types)
                        if !filtered.isEmpty {
                            typeGroupSection(kind: kind, types: filtered)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedTypeName) { _, target in
                guard let target else { return }
                Task { @MainActor in
                    if let type = schema.type(named: target) {
                        expandedSections.insert(type.kind.rawValue)
                        expandedTypes.insert(target)
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func typeGroupSection(kind: GraphQLTypeKind, types: [GraphQLFullType]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedSections.contains(kind.rawValue) },
            set: { if $0 { expandedSections.insert(kind.rawValue) } else { expandedSections.remove(kind.rawValue) } }
        )) {
            ForEach(types) { type in
                typeRow(type)
            }
        } label: {
            Label("\(kind.displayName) (\(types.count))", systemImage: kind.iconName)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func typeRow(_ type: GraphQLFullType) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedTypes.contains(type.name) },
            set: { if $0 { expandedTypes.insert(type.name) } else { expandedTypes.remove(type.name) } }
        )) {
            TypeDetailView(type: type, selectedTypeName: $selectedTypeName)
        } label: {
            Label(type.name, systemImage: type.kind.iconName)
                .lineLimit(1)
                .help(type.name)
        }
        .id(type.name)
    }

    private func filteredTypes(_ types: [GraphQLFullType]) -> [GraphQLFullType] {
        guard !searchText.isEmpty else { return types }
        let query = searchText
        return types.filter { type in
            type.name.localizedStandardContains(query) ||
            (type.fields?.contains { $0.name.localizedStandardContains(query) } ?? false) ||
            (type.inputFields?.contains { $0.name.localizedStandardContains(query) } ?? false) ||
            (type.enumValues?.contains { $0.name.localizedStandardContains(query) } ?? false)
        }
    }
}
