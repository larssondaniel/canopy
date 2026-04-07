import SwiftUI

/// Environment key for the toggle field action, used by QueryFieldRowView
/// to avoid passing closures (which defeat SwiftUI body-skip optimization).
struct ToggleFieldAction {
    let toggle: @MainActor (_ fieldName: String, _ parentPath: [String], _ rootTypeName: String?, _ segment: OperationSegment) -> Void
}

/// Environment key for the set argument action.
struct SetArgumentAction {
    let setArgument: @MainActor (_ fieldName: String, _ parentPath: [String], _ argName: String, _ value: String, _ rootTypeName: String?, _ segment: OperationSegment) -> Void
}

/// Environment key for the inspect field action.
struct InspectFieldAction {
    let inspect: @MainActor (_ field: GraphQLField, _ resolvedTypeName: String) -> Void
}

/// Environment key for running a specific operation from the sidebar.
struct RunOperationAction {
    let run: @MainActor (_ segment: OperationSegment) -> Void
}

extension EnvironmentValues {
    @Entry var toggleFieldAction: ToggleFieldAction? = nil
    @Entry var setArgumentAction: SetArgumentAction? = nil
    @Entry var inspectFieldAction: InspectFieldAction? = nil
    @Entry var runOperationAction: RunOperationAction? = nil
}

/// Visual query builder tree with collapsible operation sections and click-to-toggle
/// root operations. Stays in two-way sync with the query text editor via AST manipulation.
///
/// Shows all three operation types (Queries, Mutations, Subscriptions) simultaneously
/// as collapsible section headers in a single navigable outline.
struct QueryExplorerView: View {
    var activeTab: QueryTab?
    var astService: QueryASTService

    @SwiftUI.Environment(SchemaStore.self) private var schemaStore

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expandedPaths: Set<String> = []
    @State private var expandedSections: Set<OperationSegment> = [.queries]
    @AppStorage("showFieldTypes") private var showTypes = false
    @State private var showTypeBrowser = false
    @State private var inspectedField: InspectedFieldInfo?
    /// Snapshot of expand state before search began, for restoring on clear.
    @State private var preSearchExpandState: (paths: Set<String>, sections: Set<OperationSegment>)?
    /// Currently focused row for keyboard navigation.
    @State private var focusedRow: OutlineRowID?

    var body: some View {
        Group {
            if let endpoint = schemaStore.activeEndpoint {
                explorerContent(for: endpoint)
            } else {
                ContentUnavailableView(
                    "No Endpoint",
                    systemImage: "server.rack",
                    description: Text("Select a query tab to explore its schema.")
                )
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter fields")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { debouncedSearchText = searchText }
        }
        .task(id: activeTab?.query) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            astService.parse(activeTab?.query ?? "")
        }
        .onChange(of: debouncedSearchText) { oldValue, newValue in
            if oldValue.isEmpty && !newValue.isEmpty {
                // Search started — snapshot expand state
                preSearchExpandState = (paths: expandedPaths, sections: expandedSections)
            } else if !oldValue.isEmpty && newValue.isEmpty {
                // Search cleared — restore expand state
                if let snapshot = preSearchExpandState {
                    expandedPaths = snapshot.paths
                    expandedSections = snapshot.sections
                    preSearchExpandState = nil
                }
            }
        }
        .onChange(of: expandedSections) { _, newValue in
            if let endpoint = schemaStore.activeEndpoint {
                ExpandStateStore.saveExpandedSections(newValue, for: endpoint)
            }
        }
        .onChange(of: expandedPaths) { _, newValue in
            if let endpoint = schemaStore.activeEndpoint {
                ExpandStateStore.saveExpandedPaths(newValue, for: endpoint)
            }
        }
        .task(id: schemaStore.activeEndpoint) {
            // Load persisted expand state when endpoint changes
            guard let endpoint = schemaStore.activeEndpoint else { return }
            expandedSections = ExpandStateStore.loadExpandedSections(for: endpoint)
            expandedPaths = ExpandStateStore.loadExpandedPaths(for: endpoint)
        }
    }

    // MARK: - Explorer Content

    @ViewBuilder
    private func explorerContent(for endpoint: String) -> some View {
        switch schemaStore.state(for: endpoint) {
        case .idle:
            ContentUnavailableView {
                Label("Schema Not Loaded", systemImage: "arrow.down.circle")
            } description: {
                Text("Fetch the schema to explore and build queries.")
            } actions: {
                Button("Fetch Schema") {
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
            explorerTree(schema: schema, endpoint: endpoint)
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

    // MARK: - Available Segments

    private func availableSegments(for schema: GraphQLSchema) -> [(segment: OperationSegment, typeName: String, type: GraphQLFullType)] {
        var result: [(segment: OperationSegment, typeName: String, type: GraphQLFullType)] = []
        if let name = schema.queryTypeName, let type = schema.type(named: name) {
            result.append((.queries, name, type))
        }
        if let name = schema.mutationTypeName, let type = schema.type(named: name) {
            result.append((.mutations, name, type))
        }
        if let name = schema.subscriptionTypeName, let type = schema.type(named: name) {
            result.append((.subscriptions, name, type))
        }
        return result
    }

    // MARK: - Explorer Tree

    @ViewBuilder
    private func explorerTree(schema: GraphQLSchema, endpoint: String) -> some View {
        let segments = availableSegments(for: schema)

        let toggleAction = ToggleFieldAction { fieldName, parentPath, rootTypeName, segment in
            guard let tab = activeTab else { return }
            let newQuery = astService.toggleField(
                fieldName: fieldName,
                parentPath: parentPath,
                schema: schema,
                currentQuery: tab.query,
                rootTypeName: rootTypeName,
                segment: segment
            )
            tab.query = newQuery
        }

        let setArgAction = SetArgumentAction { fieldName, parentPath, argName, value, rootTypeName, segment in
            guard let tab = activeTab else { return }
            var allArgs = astService.argumentValues[segment]?[(parentPath + [fieldName]).joined(separator: "/")] ?? [:]
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allArgs.removeValue(forKey: argName)
            } else {
                allArgs[argName] = value
            }
            let newQuery = astService.setArguments(
                fieldName: fieldName,
                parentPath: parentPath,
                arguments: allArgs,
                schema: schema,
                currentQuery: tab.query,
                rootTypeName: rootTypeName,
                segment: segment
            )
            tab.query = newQuery
        }

        let hasParseError = astService.parseError != nil
        let isDisabled = activeTab == nil

        VStack(spacing: 0) {
            List {
                if hasParseError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Showing last valid state")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(segments, id: \.segment) { item in
                    let selectedPaths = astService.selectedPaths[item.segment] ?? []
                    let argValues = astService.argumentValues[item.segment] ?? [:]
                    let fieldCount = item.type.fields?.count ?? 0
                    let isSectionExpanded = expandedSections.contains(item.segment)
                    let matchCount = searchMatchCount(for: item.type)
                    let hasSearchText = !debouncedSearchText.isEmpty

                    // During search: auto-expand sections with matches, hide sections with no matches
                    let effectivelyExpanded = hasSearchText ? (matchCount > 0) : isSectionExpanded
                    if !hasSearchText || matchCount > 0 {
                        Section(isExpanded: Binding(
                            get: { effectivelyExpanded },
                            set: { newValue in
                                if !hasSearchText {
                                    if newValue {
                                        expandedSections.insert(item.segment)
                                    } else {
                                        expandedSections.remove(item.segment)
                                    }
                                }
                            }
                        )) {
                            RootFieldListView(
                                rootType: item.type,
                                rootTypeName: item.typeName,
                                operationType: item.segment,
                                schema: schema,
                                searchText: debouncedSearchText,
                                selectedPaths: selectedPaths,
                                argumentValues: argValues,
                                isDisabled: isDisabled,
                                showTypes: showTypes,
                                astService: astService,
                                activeTab: activeTab,
                                expandedPaths: $expandedPaths
                            )
                        } header: {
                            SectionHeaderRow(
                                segment: item.segment,
                                fieldCount: fieldCount,
                                matchCount: matchCount,
                                isSearching: hasSearchText,
                                hasSelectedFields: !selectedPaths.isEmpty
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 4)
            .environment(\.toggleFieldAction, toggleAction)
            .environment(\.setArgumentAction, setArgAction)
            .environment(\.inspectFieldAction, InspectFieldAction { field, resolvedTypeName in
                inspectedField = InspectedFieldInfo(field: field, resolvedTypeName: resolvedTypeName)
            })
            .popover(item: $inspectedField) { info in
                FieldInspectPopover(field: info.field, resolvedTypeName: info.resolvedTypeName)
            }
            .outlineKeyboardNavigation(
                focusedRow: $focusedRow,
                expandedPaths: $expandedPaths,
                expandedSections: $expandedSections,
                searchText: $searchText,
                visibleRows: computeVisibleRows(segments: segments),
                toggleRow: { row in
                    handleRowToggle(row, schema: schema)
                }
            )
            .focusable()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showTypes) {
                    Image(systemName: showTypes ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)
                .help(showTypes ? "Hide Types" : "Show Types")

                Button {
                    showTypeBrowser = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("Browse Types")

                Button {
                    schemaStore.fetchSchema(endpoint: endpoint, force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Schema")
            }
        }
        .sheet(isPresented: $showTypeBrowser) {
            TypeBrowserSheet()
        }
    }

    // MARK: - Search Helpers

    private func searchMatchCount(for rootType: GraphQLFullType) -> Int {
        guard !debouncedSearchText.isEmpty else { return 0 }
        let query = debouncedSearchText.lowercased()
        return rootType.fields?.filter { $0.name.lowercased().contains(query) }.count ?? 0
    }

    // MARK: - Keyboard Navigation

    /// Build the flat list of visible row IDs for keyboard navigation.
    private func computeVisibleRows(segments: [(segment: OperationSegment, typeName: String, type: GraphQLFullType)]) -> [OutlineRowID] {
        var rows: [OutlineRowID] = []
        let hasSearch = !debouncedSearchText.isEmpty

        for item in segments {
            let matchCount = searchMatchCount(for: item.type)
            let isVisible = !hasSearch || matchCount > 0
            guard isVisible else { continue }

            rows.append(.section(item.segment))

            let isSectionExpanded = hasSearch ? (matchCount > 0) : expandedSections.contains(item.segment)
            guard isSectionExpanded else { continue }

            let allFields = item.type.fields ?? []
            let fields: [GraphQLField]
            if hasSearch {
                let query = debouncedSearchText.lowercased()
                fields = allFields.filter { $0.name.lowercased().contains(query) }
            } else {
                fields = allFields
            }

            for field in fields {
                rows.append(.operation(item.segment, field.name))
                // If this operation is expanded, add its visible sub-fields
                // (only first level for now — deeper nesting handled by tree)
            }
        }
        return rows
    }

    /// Handle space/toggle on a focused row.
    private func handleRowToggle(_ row: OutlineRowID, schema: GraphQLSchema) {
        switch row {
        case .section(let segment):
            withAnimation {
                if expandedSections.contains(segment) {
                    expandedSections.remove(segment)
                } else {
                    expandedSections.insert(segment)
                }
            }
        case .operation(_, let fieldName):
            withAnimation {
                if expandedPaths.contains(fieldName) {
                    expandedPaths.remove(fieldName)
                } else {
                    expandedPaths.insert(fieldName)
                }
            }
        case .field(let pathKey):
            // Toggle the field checkbox via the toggle action
            let components = pathKey.split(separator: "/").map(String.init)
            guard let fieldName = components.last else { return }
            let parentPath = Array(components.dropLast())
            // Find the segment for this field — check which segment's paths contain a prefix
            for (seg, paths) in astService.selectedPaths {
                let root = components.first ?? ""
                if paths.contains(root) || (astService.selectedPaths[seg] ?? []).isEmpty == false {
                    // This is a simplification — in practice, fields are always under expanded operations
                    // which belong to a known segment
                    break
                }
                _ = seg // suppress unused warning
            }
            // Field toggles are handled by the row views directly
            break
        }
    }
}

// MARK: - Section Header Row

private struct SectionHeaderRow: View {
    let segment: OperationSegment
    let fieldCount: Int
    let matchCount: Int
    let isSearching: Bool
    let hasSelectedFields: Bool
    @SwiftUI.Environment(\.runOperationAction) private var runAction

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: segment.icon)
                .foregroundStyle(segment.accentColor)
                .frame(width: 16)

            Text(segment.rawValue)
                .fontWeight(.semibold)

            Group {
                if isSearching && matchCount > 0 {
                    Text("(\(matchCount) of \(fieldCount))")
                } else {
                    Text("(\(fieldCount))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if hasSelectedFields, let runAction {
                Button {
                    runAction.run(segment)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(segment.accentColor)
                }
                .buttonStyle(.plain)
                .help("Run \(segment.rawValue.dropLast())") // "Run Query", "Run Mutation", etc.
                .disabled(segment == .subscriptions) // Subscriptions not yet supported
            }
        }
        .font(.callout)
        .lineLimit(1)
    }
}

// MARK: - Root Field List

private struct RootFieldListView: View {
    let rootType: GraphQLFullType
    let rootTypeName: String
    let operationType: OperationSegment
    let schema: GraphQLSchema
    let searchText: String
    let selectedPaths: Set<String>
    let argumentValues: [String: [String: String]]
    let isDisabled: Bool
    let showTypes: Bool
    let astService: QueryASTService
    let activeTab: QueryTab?
    @Binding var expandedPaths: Set<String>

    @SwiftUI.Environment(\.toggleFieldAction) private var toggleAction

    var body: some View {
        let allFields = rootType.fields ?? []
        let fields = filterFields(allFields)

        if fields.isEmpty && !searchText.isEmpty {
            ContentUnavailableView(
                "No matching fields",
                systemImage: "magnifyingglass"
            )
        } else {
            ForEach(fields, id: \.name) { field in
                let typeRef = field.type.toTypeRef()
                let namedType = typeRef.namedType
                let returnType = schema.type(named: namedType)
                let isObject: Bool = {
                    guard let rt = returnType else { return false }
                    switch rt.kind {
                    case .object, .interface: return (rt.fields?.isEmpty == false)
                    case .union: return true
                    default: return false
                    }
                }()
                let pathKey = field.name
                let isSelected = selectedPaths.contains(pathKey)

                RootExpandableFieldView(
                    field: field,
                    typeRef: typeRef,
                    namedType: namedType,
                    isObject: isObject,
                    isSelected: isSelected,
                    operationType: operationType,
                    rootTypeName: rootTypeName,
                    schema: schema,
                    searchText: searchText,
                    selectedPaths: selectedPaths,
                    argumentValues: argumentValues,
                    isDisabled: isDisabled,
                    showTypes: showTypes,
                    astService: astService,
                    activeTab: activeTab,
                    expandedPaths: $expandedPaths
                )
            }
        }
    }

    private func filterFields(_ fields: [GraphQLField]) -> [GraphQLField] {
        guard !searchText.isEmpty else { return fields }
        let query = searchText.lowercased()
        return fields.filter { $0.name.lowercased().contains(query) }
    }
}

// MARK: - Root Expandable Field View

private struct RootExpandableFieldView: View {
    let field: GraphQLField
    let typeRef: GraphQLTypeRef
    let namedType: String
    let isObject: Bool
    let isSelected: Bool
    let operationType: OperationSegment
    let rootTypeName: String
    let schema: GraphQLSchema
    let searchText: String
    let selectedPaths: Set<String>
    let argumentValues: [String: [String: String]]
    let isDisabled: Bool
    let showTypes: Bool
    let astService: QueryASTService
    let activeTab: QueryTab?
    @Binding var expandedPaths: Set<String>

    @SwiftUI.Environment(\.toggleFieldAction) private var toggleAction

    var body: some View {
        if isObject {
            DisclosureGroup(isExpanded: rootExpandedBinding) {
                // Arguments
                ForEach(field.args, id: \.name) { arg in
                    let argTypeRef = arg.type.toTypeRef()
                    let hasValue = (argumentValues[field.name]?[arg.name]) != nil
                    let isRequired: Bool = if case .nonNull = argTypeRef { true } else { false }
                    ArgumentRowView(
                        argName: arg.name,
                        argTypeName: argTypeRef.displayString,
                        currentValue: argumentValues[field.name]?[arg.name] ?? "",
                        isChecked: hasValue,
                        isRequired: isRequired,
                        isFieldSelected: isSelected,
                        isDisabled: isDisabled,
                        fieldName: field.name,
                        parentPath: [],
                        rootTypeName: rootTypeName,
                        operationType: operationType
                    )
                }

                // Sub-fields
                if let returnType = schema.type(named: namedType), let subFields = returnType.fields {
                    let filtered = filterFields(subFields)
                    FieldListView(
                        fields: filtered,
                        schema: schema,
                        parentPath: [field.name],
                        rootTypeName: rootTypeName,
                        operationType: operationType,
                        selectedPaths: selectedPaths,
                        argumentValues: argumentValues,
                        isDisabled: isDisabled,
                        searchText: searchText,
                        showTypes: showTypes,
                        expandedPaths: $expandedPaths,
                        ancestorTypes: [namedType]
                    )
                }
            } label: {
                RootOperationRowView(
                    fieldName: field.name,
                    typeName: typeRef.displayString,
                    operationType: operationType,
                    isSelected: isSelected,
                    isDeprecated: field.isDeprecated,
                    showTypes: showTypes,
                    inspectableField: field
                )
                .onTapGesture {
                    withAnimation {
                        rootExpandedBinding.wrappedValue = !expandedPaths.contains(field.name)
                    }
                }
            }
        } else {
            // Scalar root field — just show the row with a tap handler
            RootOperationRowView(
                fieldName: field.name,
                typeName: typeRef.displayString,
                operationType: operationType,
                isSelected: isSelected,
                isDeprecated: field.isDeprecated,
                showTypes: showTypes,
                inspectableField: field
            )
            .onTapGesture {
                guard !isDisabled else { return }
                toggleAction?.toggle(field.name, [], rootTypeName, operationType)
            }
        }
    }

    /// Unified binding: expanding = select in AST, collapsing = deselect from AST.
    private var rootExpandedBinding: Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(field.name) },
            set: { newValue in
                guard !isDisabled else { return }

                if newValue {
                    // Expanding -> select the operation in the AST
                    if !isSelected {
                        if let preserved = astService.restoreSelections(forRoot: field.name, segment: operationType) {
                            // Step 1: Add the root (which auto-adds a default sub-selection)
                            toggleAction?.toggle(field.name, [], rootTypeName, operationType)
                            if let tab = activeTab {
                                let rootPrefix = field.name + "/"
                                let preservedChildren = preserved.filter { $0.hasPrefix(rootPrefix) }

                                // Step 2: Add preserved children that aren't already selected
                                for path in preservedChildren.sorted() {
                                    if !astService.isFieldSelected(
                                        fieldName: path.split(separator: "/").last.map(String.init) ?? "",
                                        parentPath: path.split(separator: "/").dropLast().map(String.init),
                                        segment: operationType
                                    ) {
                                        let components = path.split(separator: "/").map(String.init)
                                        if components.count >= 2 {
                                            let childField = components.last!
                                            let parentPath = Array(components.dropLast())
                                            let newQuery = astService.toggleField(
                                                fieldName: childField,
                                                parentPath: parentPath,
                                                schema: schema,
                                                currentQuery: tab.query,
                                                rootTypeName: rootTypeName,
                                                segment: operationType
                                            )
                                            tab.query = newQuery
                                        }
                                    }
                                }

                                // Step 3: Remove default sub-fields that weren't in the preserved set
                                let currentChildren = (astService.selectedPaths[operationType] ?? []).filter { $0.hasPrefix(rootPrefix) }
                                for path in currentChildren where !preservedChildren.contains(path) {
                                    let components = path.split(separator: "/").map(String.init)
                                    if components.count >= 2 {
                                        let childField = components.last!
                                        let parentPath = Array(components.dropLast())
                                        let newQuery = astService.toggleField(
                                            fieldName: childField,
                                            parentPath: parentPath,
                                            schema: schema,
                                            currentQuery: tab.query,
                                            rootTypeName: rootTypeName,
                                            segment: operationType
                                        )
                                        tab.query = newQuery
                                    }
                                }
                            }
                        } else {
                            toggleAction?.toggle(field.name, [], rootTypeName, operationType)
                        }
                    }
                    expandedPaths.insert(field.name)
                } else {
                    // Collapsing -> deselect the operation from the AST
                    if isSelected {
                        astService.preserveSelections(forRoot: field.name, segment: operationType)
                        toggleAction?.toggle(field.name, [], rootTypeName, operationType)
                    }
                    expandedPaths.remove(field.name)
                }
            }
        )
    }

    private func filterFields(_ fields: [GraphQLField]) -> [GraphQLField] {
        guard !searchText.isEmpty else { return fields }
        let query = searchText.lowercased()
        return fields.filter { $0.name.lowercased().contains(query) }
    }
}

// MARK: - Field List

private struct FieldListView: View {
    let fields: [GraphQLField]
    let schema: GraphQLSchema
    let parentPath: [String]
    let rootTypeName: String
    let operationType: OperationSegment
    let selectedPaths: Set<String>
    let argumentValues: [String: [String: String]]
    let isDisabled: Bool
    let searchText: String
    var showTypes: Bool = false
    @Binding var expandedPaths: Set<String>
    var ancestorTypes: Set<String> = []
    var fieldCountCap: Int = 50

    var body: some View {
        let displayedFields = Array(fields.prefix(fieldCountCap))
        ForEach(displayedFields, id: \.name) { field in
            let typeRef = field.type.toTypeRef()
            let namedType = typeRef.namedType
            let returnType = schema.type(named: namedType)
            let isObject: Bool = {
                guard let rt = returnType else { return false }
                switch rt.kind {
                case .object, .interface: return (rt.fields?.isEmpty == false)
                case .union: return true
                default: return false
                }
            }()
            let isCircular = ancestorTypes.contains(namedType)
            let pathKey = (parentPath + [field.name]).joined(separator: "/")
            let isSelected = selectedPaths.contains(pathKey)

            ExplorerFieldView(
                fieldName: field.name,
                typeName: typeRef.displayString,
                returnTypeName: namedType,
                isSelected: isSelected,
                isDeprecated: field.isDeprecated,
                isObjectType: isObject,
                isCircular: isCircular,
                hasArguments: !field.args.isEmpty,
                isDisabled: isDisabled,
                parentPath: parentPath,
                fieldPath: parentPath + [field.name],
                pathKey: pathKey,
                rootTypeName: rootTypeName,
                operationType: operationType,
                showTypes: showTypes,
                inspectableField: field,
                args: field.args,
                currentArgValues: argumentValues[pathKey] ?? [:],
                subFields: isObject && !isCircular ? returnType?.fields : nil,
                schema: schema,
                searchText: searchText,
                selectedPaths: selectedPaths,
                argumentValues: argumentValues,
                expandedPaths: $expandedPaths,
                ancestorTypes: ancestorTypes
            )
        }
        if fields.count > fieldCountCap {
            Text("+ \(fields.count - fieldCountCap) more fields")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Explorer Field View

private struct ExplorerFieldView: View {
    let fieldName: String
    let typeName: String
    let returnTypeName: String
    let isSelected: Bool
    let isDeprecated: Bool
    let isObjectType: Bool
    let isCircular: Bool
    let hasArguments: Bool
    let isDisabled: Bool
    let parentPath: [String]
    let fieldPath: [String]
    let pathKey: String
    let rootTypeName: String
    let operationType: OperationSegment
    var showTypes: Bool = false
    var inspectableField: GraphQLField? = nil
    let args: [GraphQLInputValue]
    let currentArgValues: [String: String]
    let subFields: [GraphQLField]?

    let schema: GraphQLSchema
    let searchText: String
    let selectedPaths: Set<String>
    let argumentValues: [String: [String: String]]
    @Binding var expandedPaths: Set<String>
    var ancestorTypes: Set<String> = []

    var body: some View {
        if isObjectType && !isCircular {
            expandableField
        } else {
            QueryFieldRowView(
                fieldName: fieldName,
                typeName: typeName,
                isSelected: isSelected,
                isDeprecated: isDeprecated,
                isCircular: isCircular,
                hasArguments: hasArguments,
                isDisabled: isDisabled,
                parentPath: parentPath,
                rootTypeName: rootTypeName,
                operationType: operationType,
                showTypes: showTypes,
                inspectableField: inspectableField
            )
        }
    }

    @ViewBuilder
    private var expandableField: some View {
        DisclosureGroup(isExpanded: expandedBinding(for: pathKey)) {
            ForEach(args, id: \.name) { arg in
                let typeRef = arg.type.toTypeRef()
                let hasValue = currentArgValues[arg.name] != nil
                let isRequired: Bool = if case .nonNull = typeRef { true } else { false }
                ArgumentRowView(
                    argName: arg.name,
                    argTypeName: typeRef.displayString,
                    currentValue: currentArgValues[arg.name] ?? "",
                    isChecked: hasValue,
                    isRequired: isRequired,
                    isFieldSelected: isSelected,
                    isDisabled: isDisabled,
                    fieldName: fieldName,
                    parentPath: parentPath,
                    rootTypeName: rootTypeName,
                    operationType: operationType
                )
            }

            if let subFields {
                let filtered = filterFields(subFields)
                var newAncestors = ancestorTypes
                let _ = newAncestors.insert(returnTypeName)
                FieldListView(
                    fields: filtered,
                    schema: schema,
                    parentPath: fieldPath,
                    rootTypeName: rootTypeName,
                    operationType: operationType,
                    selectedPaths: selectedPaths,
                    argumentValues: argumentValues,
                    isDisabled: isDisabled,
                    searchText: searchText,
                    showTypes: showTypes,
                    expandedPaths: $expandedPaths,
                    ancestorTypes: newAncestors
                )
            }
        } label: {
            QueryFieldRowView(
                fieldName: fieldName,
                typeName: typeName,
                isSelected: isSelected,
                isDeprecated: isDeprecated,
                isCircular: false,
                hasArguments: hasArguments,
                isDisabled: isDisabled,
                parentPath: parentPath,
                rootTypeName: rootTypeName,
                operationType: operationType,
                showTypes: showTypes,
                inspectableField: inspectableField
            )
        }
    }

    private func expandedBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(key) },
            set: { if $0 { expandedPaths.insert(key) } else { expandedPaths.remove(key) } }
        )
    }

    private func filterFields(_ fields: [GraphQLField]) -> [GraphQLField] {
        guard !searchText.isEmpty else { return fields }
        let query = searchText.lowercased()
        return fields.filter { $0.name.lowercased().contains(query) }
    }
}

// MARK: - Argument Row View

private struct ArgumentRowView: View {
    let argName: String
    let argTypeName: String
    let currentValue: String
    let isChecked: Bool
    let isRequired: Bool
    let isFieldSelected: Bool
    let isDisabled: Bool
    let fieldName: String
    let parentPath: [String]
    var rootTypeName: String? = nil
    var operationType: OperationSegment = .queries

    @State private var editText: String = ""
    @State private var localChecked: Bool = false
    @FocusState private var isFocused: Bool
    @SwiftUI.Environment(\.setArgumentAction) private var setArgAction

    private var canInteract: Bool { isFieldSelected && !isDisabled }
    private var showInput: Bool { (isChecked || localChecked) && canInteract }

    var body: some View {
        HStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { isChecked || localChecked },
                set: { newValue in
                    if newValue {
                        localChecked = true
                    } else {
                        localChecked = false
                        editText = ""
                        setArgAction?.setArgument(fieldName, parentPath, argName, "", rootTypeName, operationType)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(!canInteract)

            Text(argName)
                .foregroundStyle(.orange)
            Text(":")
                .foregroundStyle(.secondary)
            Text(argTypeName)
                .foregroundStyle(.secondary)

            if showInput {
                Spacer()
                TextField("value", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: 100)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    .focused($isFocused)
                    .onSubmit { commitValue() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitValue() }
                    }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.leading, 8)
        .task(id: currentValue) {
            if !isFocused {
                editText = currentValue
            }
            if isChecked {
                localChecked = false
            }
        }
        .onAppear {
            editText = currentValue
        }
    }

    private func commitValue() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != currentValue {
            setArgAction?.setArgument(fieldName, parentPath, argName, trimmed, rootTypeName, operationType)
        }
    }
}
