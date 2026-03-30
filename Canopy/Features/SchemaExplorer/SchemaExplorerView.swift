import SwiftUI

struct SchemaExplorerView: View {
    @SwiftUI.Environment(SchemaStore.self) private var schemaStore

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expandedSections: Set<String> = []
    @State private var expandedTypes: Set<String> = []
    @State private var selectedTypeName: String?

    var body: some View {
        Group {
            if let endpoint = schemaStore.activeEndpoint {
                schemaContent(for: endpoint)
            } else {
                ContentUnavailableView(
                    "No Endpoint",
                    systemImage: "server.rack",
                    description: Text("Select a query tab to explore its schema.")
                )
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter types and fields")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { debouncedSearchText = searchText }
        }
    }

    // MARK: - Schema Content

    @ViewBuilder
    private func schemaContent(for endpoint: String) -> some View {
        switch schemaStore.state(for: endpoint) {
        case .idle:
            ContentUnavailableView {
                Label("Schema Not Loaded", systemImage: "arrow.down.circle")
            } description: {
                Text("Load the schema to browse types and fields.")
            } actions: {
                Button("Load Schema") {
                    schemaStore.fetchSchema(endpoint: endpoint, force: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading schema...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let schema):
            schemaTree(schema, endpoint: endpoint)
        case .error(let message):
            ContentUnavailableView {
                Label("Schema Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    schemaStore.fetchSchema(endpoint: endpoint, force: true)
                }
            }
        }
    }

    // MARK: - Schema Tree

    private func schemaTree(_ schema: GraphQLSchema, endpoint: String) -> some View {
        ScrollViewReader { proxy in
            List {
                // Root operation types
                if let queryTypeName = schema.queryTypeName,
                   let queryType = schema.type(named: queryTypeName) {
                    rootOperationSection("Queries", type: queryType, icon: "magnifyingglass")
                }

                if let mutationTypeName = schema.mutationTypeName,
                   let mutationType = schema.type(named: mutationTypeName) {
                    rootOperationSection("Mutations", type: mutationType, icon: "arrow.triangle.2.circlepath")
                }

                if let subscriptionTypeName = schema.subscriptionTypeName,
                   let subscriptionType = schema.type(named: subscriptionTypeName) {
                    rootOperationSection("Subscriptions", type: subscriptionType, icon: "antenna.radiowaves.left.and.right")
                }

                // Type groups (derived from sortOrder, excludes wrapper kinds)
                let typeKinds = GraphQLTypeKind.topLevelKinds
                let rootTypeNames: Set<String> = Set(
                    [schema.queryTypeName, schema.mutationTypeName, schema.subscriptionTypeName].compactMap { $0 }
                )

                ForEach(typeKinds, id: \.self) { kind in
                    if let types = schema.sortedTypesByKind[kind]?.filter({
                        !rootTypeNames.contains($0.name)
                    }), !types.isEmpty {
                        typeGroupSection(kind: kind, types: filteredTypes(types))
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        schemaStore.fetchSchema(endpoint: endpoint, force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Schema")
                }
            }
        }
    }

    // MARK: - Root Operation Section

    @ViewBuilder
    private func rootOperationSection(_ title: String, type: GraphQLFullType, icon: String) -> some View {
        let sectionID = "root-\(title)"
        let fields = filteredFields(type.fields ?? [])

        if debouncedSearchText.isEmpty || !fields.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedSections.contains(sectionID) },
                set: { if $0 { expandedSections.insert(sectionID) } else { expandedSections.remove(sectionID) } }
            )) {
                ForEach(fields) { field in
                    FieldRowCompact(field: field, selectedTypeName: $selectedTypeName)
                }
            } label: {
                Label(title, systemImage: icon)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Type Group Section

    @ViewBuilder
    private func typeGroupSection(kind: GraphQLTypeKind, types: [GraphQLFullType]) -> some View {
        if !types.isEmpty {
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
    }

    @ViewBuilder
    private func typeRow(_ type: GraphQLFullType) -> some View {
        let isExpanded = Binding(
            get: { expandedTypes.contains(type.name) },
            set: { if $0 { expandedTypes.insert(type.name) } else { expandedTypes.remove(type.name) } }
        )

        DisclosureGroup(isExpanded: isExpanded) {
            TypeDetailView(type: type, selectedTypeName: $selectedTypeName)
        } label: {
            Label(type.name, systemImage: type.kind.iconName)
                .lineLimit(1)
                .help(type.name)
        }
        .id(type.name)
    }

    // MARK: - Filtering

    private func filteredTypes(_ types: [GraphQLFullType]) -> [GraphQLFullType] {
        guard !debouncedSearchText.isEmpty else { return types }
        let query = debouncedSearchText
        return types.filter { type in
            type.name.localizedStandardContains(query) ||
            (type.fields?.contains { $0.name.localizedStandardContains(query) } ?? false) ||
            (type.inputFields?.contains { $0.name.localizedStandardContains(query) } ?? false) ||
            (type.enumValues?.contains { $0.name.localizedStandardContains(query) } ?? false)
        }
    }

    private func filteredFields(_ fields: [GraphQLField]) -> [GraphQLField] {
        guard !debouncedSearchText.isEmpty else { return fields }
        return fields.filter { $0.name.localizedStandardContains(debouncedSearchText) }
    }
}

// MARK: - Compact Field Row (for root operations)

private struct FieldRowCompact: View {
    let field: GraphQLField
    @Binding var selectedTypeName: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(field.name)
                .fontWeight(.medium)
                .strikethrough(field.isDeprecated)
                .foregroundStyle(field.isDeprecated ? .secondary : .primary)

            Text(":")
                .foregroundStyle(.secondary)

            TypeRefView(typeRef: field.type.toTypeRef()) { name in
                selectedTypeName = name
            }
        }
        .font(.system(.caption, design: .monospaced))
        .help(field.description ?? field.name)
    }
}
