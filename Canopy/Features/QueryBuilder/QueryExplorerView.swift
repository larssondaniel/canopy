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
    @SwiftUI.Environment(ProjectWindowState.self) private var windowState

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
    /// Currently hovered row for hover highlight.
    @State private var hoveredRow: OutlineRowID?
    /// Incremented to trigger argument checkbox toggle from keyboard.
    @State private var argToggle = ArgumentToggleTrigger()
    /// Keyboard focus state for the sidebar list.
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        Group {
            if let endpoint = windowState.activeEndpoint {
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
            let didParse = astService.parse(activeTab?.query ?? "")
            if didParse {
                syncExpandStateFromAST()
            }
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
            if let endpoint = windowState.activeEndpoint {
                ExpandStateStore.saveExpandedSections(newValue, for: endpoint)
            }
        }
        .onChange(of: expandedPaths) { _, newValue in
            if let endpoint = windowState.activeEndpoint {
                ExpandStateStore.saveExpandedPaths(newValue, for: endpoint)
            }
        }
        .task(id: windowState.activeEndpoint) {
            // Load persisted expand state when endpoint changes
            guard let endpoint = windowState.activeEndpoint else { return }
            expandedSections = ExpandStateStore.loadExpandedSections(for: endpoint)
            expandedPaths = ExpandStateStore.loadExpandedPaths(for: endpoint)
            astService.preservedSelections = ExpandStateStore.loadPreservedSelections(for: endpoint)
        }
        .onChange(of: astService.preservedSelections) { _, newValue in
            if let endpoint = windowState.activeEndpoint {
                ExpandStateStore.savePreservedSelections(newValue, for: endpoint)
            }
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
                    schemaStore.fetchSchema(
                        endpoint: endpoint,
                        method: windowState.activeMethod,
                        auth: windowState.activeAuth.toAuthConfiguration(),
                        headers: windowState.activeHeaders,
                        force: true
                    )
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
                    schemaStore.fetchSchema(
                        endpoint: endpoint,
                        method: windowState.activeMethod,
                        auth: windowState.activeAuth.toAuthConfiguration(),
                        headers: windowState.activeHeaders,
                        force: true
                    )
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
                        DisclosureGroup(isExpanded: Binding(
                            get: { effectivelyExpanded },
                            set: { newValue in
                                if !hasSearchText {
                                    withAnimation {
                                        if newValue {
                                            expandedSections.insert(item.segment)
                                        } else {
                                            expandedSections.remove(item.segment)
                                        }
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
                        } label: {
                            SectionHeaderRow(
                                segment: item.segment,
                                fieldCount: fieldCount,
                                matchCount: matchCount,
                                isSearching: hasSearchText,
                                hasSelectedFields: !selectedPaths.isEmpty
                            )
                            .onTapGesture {
                                focusedRow = .section(item.segment)
                                isSidebarFocused = true
                                guard !hasSearchText else { return }
                                withAnimation {
                                    if expandedSections.contains(item.segment) {
                                        expandedSections.remove(item.segment)
                                    } else {
                                        expandedSections.insert(item.segment)
                                    }
                                }
                            }
                        }
                        .outlineRowHighlight(.section(item.segment))
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 22)
            .environment(\.focusedOutlineRow, focusedRow)
            .environment(\.hoveredOutlineRow, hoveredRow)
            .environment(\.setFocusedRowAction, SetFocusedRowAction { row in
                focusedRow = row
                isSidebarFocused = true
            })
            .environment(\.setHoveredRowAction, SetHoveredRowAction { row in
                hoveredRow = row
            })
            .environment(\.argumentToggleTrigger, argToggle)
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
                visibleRows: computeVisibleRows(segments: segments, schema: schema),
                toggleRow: { row in
                    handleRowToggle(row, schema: schema)
                }
            )
            .focusable()
            .focused($isSidebarFocused)
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
                    schemaStore.fetchSchema(
                        endpoint: endpoint,
                        method: windowState.activeMethod,
                        auth: windowState.activeAuth.toAuthConfiguration(),
                        headers: windowState.activeHeaders,
                        force: true
                    )
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

    // MARK: - Editor → Sidebar Sync

    /// After an editor-initiated parse, sync sidebar expand state with the AST.
    /// Expands nodes for selected fields and collapses root operations that are no longer selected.
    private func syncExpandStateFromAST() {
        var pathsToExpand: Set<String> = []
        var selectedRoots: Set<String> = []
        for (_, paths) in astService.selectedPaths {
            for path in paths {
                let components = path.split(separator: "/")
                if let root = components.first {
                    selectedRoots.insert(String(root))
                }
                // Expand root field and all intermediate ancestor paths
                for i in 1...components.count {
                    pathsToExpand.insert(components.prefix(i).joined(separator: "/"))
                }
            }
        }

        var sectionsToExpand: Set<OperationSegment> = []
        for (segment, paths) in astService.selectedPaths where !paths.isEmpty {
            sectionsToExpand.insert(segment)
        }

        // Add paths for selected fields
        var newPaths = expandedPaths.union(pathsToExpand)

        // Collapse root operations that are no longer selected in the AST
        // (e.g., user deleted the query text in the editor)
        let rootExpandedPaths = expandedPaths.filter { !$0.contains("/") }
        for root in rootExpandedPaths where !selectedRoots.contains(root) {
            newPaths.remove(root)
        }

        let newSections = expandedSections.union(sectionsToExpand)
        if newPaths != expandedPaths { expandedPaths = newPaths }
        if newSections != expandedSections { expandedSections = newSections }
    }

    // MARK: - Search Helpers

    private func searchMatchCount(for rootType: GraphQLFullType) -> Int {
        guard !debouncedSearchText.isEmpty else { return 0 }
        let query = debouncedSearchText.lowercased()
        return rootType.fields?.filter { $0.name.lowercased().contains(query) }.count ?? 0
    }

    // MARK: - Keyboard Navigation

    /// Build the flat list of visible row IDs for keyboard navigation.
    private func computeVisibleRows(segments: [(segment: OperationSegment, typeName: String, type: GraphQLFullType)], schema: GraphQLSchema) -> [OutlineRowID] {
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

                // If this root operation is expanded, include arguments then sub-fields
                if expandedPaths.contains(field.name) {
                    // Arguments come first (shown before sub-fields in the view)
                    for arg in field.args {
                        rows.append(.argument("\(field.name)/@\(arg.name)"))
                    }

                    let returnTypeName = field.type.toTypeRef().namedType
                    if let returnType = schema.type(named: returnTypeName) {
                        collectVisibleFields(
                            parentType: returnType,
                            parentPath: [field.name],
                            schema: schema,
                            ancestorTypes: [returnTypeName],
                            into: &rows
                        )
                    }
                }
            }
        }
        return rows
    }

    /// Recursively collect visible sub-field row IDs for expanded fields.
    private func collectVisibleFields(
        parentType: GraphQLFullType,
        parentPath: [String],
        schema: GraphQLSchema,
        ancestorTypes: Set<String>,
        into rows: inout [OutlineRowID]
    ) {
        guard let fields = parentType.fields else { return }
        for field in fields {
            let pathKey = (parentPath + [field.name]).joined(separator: "/")
            rows.append(.field(pathKey))

            // If this field is expanded and returns an object type, recurse
            if expandedPaths.contains(pathKey) {
                // Arguments come first (shown before sub-fields in the view)
                for arg in field.args {
                    rows.append(.argument("\(pathKey)/@\(arg.name)"))
                }

                let namedType = field.type.toTypeRef().namedType
                guard !ancestorTypes.contains(namedType) else { continue } // circular
                if let returnType = schema.type(named: namedType),
                   returnType.kind == .object || returnType.kind == .interface || returnType.kind == .union {
                    var newAncestors = ancestorTypes
                    newAncestors.insert(namedType)
                    collectVisibleFields(
                        parentType: returnType,
                        parentPath: parentPath + [field.name],
                        schema: schema,
                        ancestorTypes: newAncestors,
                        into: &rows
                    )
                }
            }
        }
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
        case .operation(let segment, let fieldName):
            guard let tab = activeTab else { return }
            let segments = availableSegments(for: schema)
            guard let segmentData = segments.first(where: { $0.segment == segment }) else { return }
            let isSelected = astService.isFieldSelected(fieldName: fieldName, parentPath: [], segment: segment)

            withAnimation {
                if expandedPaths.contains(fieldName) {
                    // Collapsing
                    if isSelected {
                        let newQuery = astService.collapseRoot(
                            fieldName: fieldName,
                            segment: segment,
                            schema: schema,
                            currentQuery: tab.query,
                            rootTypeName: segmentData.typeName
                        )
                        tab.query = newQuery
                    }
                    expandedPaths.remove(fieldName)
                } else {
                    // Expanding
                    if !isSelected {
                        let newQuery = astService.expandRoot(
                            fieldName: fieldName,
                            segment: segment,
                            schema: schema,
                            currentQuery: tab.query,
                            rootTypeName: segmentData.typeName
                        )
                        tab.query = newQuery
                    }
                    expandedPaths.insert(fieldName)
                }
            }
        case .field(let pathKey):
            let components = pathKey.split(separator: "/").map(String.init)
            guard let fieldName = components.last else { return }
            let parentPath = Array(components.dropLast())
            guard let tab = activeTab else { return }

            // Find which segment this field belongs to by checking the root field name
            let rootFieldName = components.first ?? ""
            let segments = availableSegments(for: schema)
            guard let segmentData = segments.first(where: { item in
                item.type.fields?.contains(where: { $0.name == rootFieldName }) == true
            }) else { return }

            let newQuery = astService.toggleField(
                fieldName: fieldName,
                parentPath: parentPath,
                schema: schema,
                currentQuery: tab.query,
                rootTypeName: segmentData.typeName,
                segment: segmentData.segment
            )
            tab.query = newQuery
        case .argument:
            argToggle.count += 1
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
    @SwiftUI.Environment(\.isRowHighlighted) private var isHighlighted
    @SwiftUI.Environment(\.setHoveredRowAction) private var setHoverAction
    @State private var isHoveringRun = false

    private var countLabel: String {
        if isSearching && matchCount > 0 {
            "\(matchCount) of \(fieldCount)"
        } else {
            "\(fieldCount)"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: segment.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHighlighted ? .white.opacity(0.8) : .secondary)
                .frame(width: 16, height: 16)

            Text(segment.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHighlighted ? .white : .primary)

            Text(countLabel)
                .font(.system(.caption2, weight: .medium))
                .foregroundColor(isHighlighted ? .white.opacity(0.7) : .gray)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(isHighlighted ? Color.white.opacity(0.2) : Color.gray.opacity(0.15), in: Capsule())

            Spacer(minLength: 4)

            if hasSelectedFields, let runAction {
                Button {
                    runAction.run(segment)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isHighlighted ? .white : isHoveringRun ? .primary : .gray)
                        .frame(width: 18, height: 18)
                        .background(
                            isHoveringRun ? (isHighlighted ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)) : .clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringRun = $0 }
                .help("Run \(segment.rawValue.dropLast())")
                .disabled(segment == .subscriptions)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            setHoverAction?.setHover(hovering ? .section(segment) : nil)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(segment.rawValue), \(fieldCount) fields")
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
    @SwiftUI.Environment(\.setFocusedRowAction) private var setFocusAction

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
                        operationType: operationType,
                        rowID: .argument("\(field.name)/@\(arg.name)")
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
                    setFocusAction?.setFocus(.operation(operationType, field.name))
                    withAnimation {
                        rootExpandedBinding.wrappedValue = !expandedPaths.contains(field.name)
                    }
                }
            }
            .outlineRowHighlight(.operation(operationType, field.name))
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
                setFocusAction?.setFocus(.operation(operationType, field.name))
                guard !isDisabled else { return }
                toggleAction?.toggle(field.name, [], rootTypeName, operationType)
            }
            .outlineRowHighlight(.operation(operationType, field.name))
        }
    }

    /// Unified binding: expanding = select in AST via expandRoot, collapsing = deselect via collapseRoot.
    private var rootExpandedBinding: Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(field.name) },
            set: { newValue in
                guard !isDisabled else { return }

                if newValue {
                    if !isSelected, let tab = activeTab {
                        let newQuery = astService.expandRoot(
                            fieldName: field.name,
                            segment: operationType,
                            schema: schema,
                            currentQuery: tab.query,
                            rootTypeName: rootTypeName
                        )
                        tab.query = newQuery
                    }
                    expandedPaths.insert(field.name)
                } else {
                    if isSelected, let tab = activeTab {
                        let newQuery = astService.collapseRoot(
                            fieldName: field.name,
                            segment: operationType,
                            schema: schema,
                            currentQuery: tab.query,
                            rootTypeName: rootTypeName
                        )
                        tab.query = newQuery
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

    @SwiftUI.Environment(\.setFocusedRowAction) private var setFocusAction

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
            .outlineRowHighlight(.field(pathKey))
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
                    operationType: operationType,
                    rowID: .argument("\(pathKey)/@\(arg.name)")
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
        .outlineRowHighlight(.field(pathKey))
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
    var rowID: OutlineRowID? = nil

    @State private var editText: String = ""
    @State private var localChecked: Bool = false
    @FocusState private var isFocused: Bool
    @SwiftUI.Environment(\.setArgumentAction) private var setArgAction
    @SwiftUI.Environment(\.focusedOutlineRow) private var focusedRow
    @SwiftUI.Environment(\.hoveredOutlineRow) private var hoveredRow
    @SwiftUI.Environment(\.argumentToggleTrigger) private var argToggle

    private var canInteract: Bool { isFieldSelected && !isDisabled }
    private var showInput: Bool { (isChecked || localChecked) && canInteract }
    private var isRowFocused: Bool { rowID != nil && focusedRow == rowID }
    private var isRowHovered: Bool { rowID != nil && hoveredRow == rowID }

    private static let selectionColor = Color(nsColor: NSColor.controlAccentColor).opacity(0.85)
    private static let hoverColor = Color.primary.opacity(0.06)

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
                    .frame(minWidth: 60)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isFocused ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onSubmit { commitValue() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitValue() }
                    }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .listRowBackground(
            isRowFocused
                ? RoundedRectangle(cornerRadius: 7)
                    .fill(Self.selectionColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                : isRowHovered
                    ? RoundedRectangle(cornerRadius: 7)
                        .fill(Self.hoverColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                    : nil
        )
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
        .onChange(of: argToggle.count) { _, _ in
            guard isRowFocused, canInteract else { return }
            if isChecked || localChecked {
                // Toggle OFF: clear the argument
                localChecked = false
                editText = ""
                setArgAction?.setArgument(fieldName, parentPath, argName, "", rootTypeName, operationType)
            } else {
                // Toggle ON: show the input field
                localChecked = true
            }
        }
    }

    private func commitValue() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != currentValue {
            setArgAction?.setArgument(fieldName, parentPath, argName, trimmed, rootTypeName, operationType)
        }
    }
}
