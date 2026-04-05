import SwiftUI

/// Environment key for the toggle field action, used by QueryFieldRowView
/// to avoid passing closures (which defeat SwiftUI body-skip optimization).
struct ToggleFieldAction {
    let toggle: @MainActor (_ fieldName: String, _ parentPath: [String], _ rootTypeName: String?) -> Void
}

/// Environment key for the set argument action.
struct SetArgumentAction {
    let setArgument: @MainActor (_ fieldName: String, _ parentPath: [String], _ argName: String, _ value: String, _ rootTypeName: String?) -> Void
}

/// Environment key for the inspect field action.
struct InspectFieldAction {
    let inspect: @MainActor (_ field: GraphQLField, _ resolvedTypeName: String) -> Void
}

extension EnvironmentValues {
    @Entry var toggleFieldAction: ToggleFieldAction? = nil
    @Entry var setArgumentAction: SetArgumentAction? = nil
    @Entry var inspectFieldAction: InspectFieldAction? = nil
}

/// Visual query builder tree with segmented operation filter and click-to-toggle
/// root operations. Stays in two-way sync with the query text editor via AST manipulation.
struct QueryExplorerView: View {
    var activeTab: QueryTab?
    var astService: QueryASTService

    @SwiftUI.Environment(SchemaStore.self) private var schemaStore

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expandedPaths: Set<String> = []
    @AppStorage("selectedOperationSegment") private var selectedSegment: String = OperationSegment.queries.rawValue
    @AppStorage("showFieldTypes") private var showTypes = false
    @State private var showTypeBrowser = false
    @State private var inspectedField: InspectedFieldInfo?

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

    private func activeSegmentData(segments: [(segment: OperationSegment, typeName: String, type: GraphQLFullType)]) -> (segment: OperationSegment, typeName: String, type: GraphQLFullType)? {
        let current = OperationSegment(rawValue: selectedSegment)
        return segments.first(where: { $0.segment == current }) ?? segments.first
    }

    // MARK: - Explorer Tree

    @ViewBuilder
    private func explorerTree(schema: GraphQLSchema, endpoint: String) -> some View {
        let segments = availableSegments(for: schema)
        let active = activeSegmentData(segments: segments)

        let toggleAction = ToggleFieldAction { fieldName, parentPath, rootTypeName in
            guard let tab = activeTab else { return }
            let newQuery = astService.toggleField(
                fieldName: fieldName,
                parentPath: parentPath,
                schema: schema,
                currentQuery: tab.query,
                rootTypeName: rootTypeName
            )
            tab.query = newQuery
        }

        let setArgAction = SetArgumentAction { fieldName, parentPath, argName, value, rootTypeName in
            guard let tab = activeTab else { return }
            var allArgs = astService.argumentValues[(parentPath + [fieldName]).joined(separator: "/")] ?? [:]
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
                rootTypeName: rootTypeName
            )
            tab.query = newQuery
        }

        // Read @Observable properties ONCE at this level.
        let selectedPaths = astService.selectedPaths
        let argValues = astService.argumentValues
        let hasParseError = astService.parseError != nil
        let multipleOps = (astService.currentDocument?.definitions.count ?? 0) > 1
        let isDisabled = activeTab == nil

        VStack(spacing: 0) {
            // Segmented filter — only show if more than one operation type
            if segments.count > 1 {
                segmentedFilter(segments: segments, schema: schema)
            }

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

                if multipleOps {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Showing first operation only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let active {
                    RootFieldListView(
                        rootType: active.type,
                        rootTypeName: active.typeName,
                        operationType: active.segment,
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
                }
            }
            .listStyle(.sidebar)
            .environment(\.toggleFieldAction, toggleAction)
            .environment(\.setArgumentAction, setArgAction)
            .environment(\.inspectFieldAction, InspectFieldAction { field, resolvedTypeName in
                inspectedField = InspectedFieldInfo(field: field, resolvedTypeName: resolvedTypeName)
            })
            .popover(item: $inspectedField) { info in
                FieldInspectPopover(field: info.field, resolvedTypeName: info.resolvedTypeName)
            }
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

    // MARK: - Segmented Filter

    @ViewBuilder
    private func segmentedFilter(segments: [(segment: OperationSegment, typeName: String, type: GraphQLFullType)], schema: GraphQLSchema) -> some View {
        GeometryReader { geo in
            let useIcons = geo.size.width < 220

            Picker("", selection: $selectedSegment) {
                ForEach(segments, id: \.segment) { item in
                    let matchCount = crossSegmentMatchCount(for: item.type)
                    if useIcons {
                        Image(systemName: item.segment.icon)
                            .help(badgeLabel(item.segment.rawValue, count: matchCount))
                            .tag(item.segment.rawValue)
                    } else {
                        Text(badgeLabel(item.segment.rawValue, count: matchCount))
                            .tag(item.segment.rawValue)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 34)
    }

    private func crossSegmentMatchCount(for rootType: GraphQLFullType) -> Int {
        guard !debouncedSearchText.isEmpty else { return 0 }
        let query = debouncedSearchText.lowercased()
        return rootType.fields?.filter { $0.name.lowercased().contains(query) }.count ?? 0
    }

    private func badgeLabel(_ base: String, count: Int) -> String {
        if count > 0 && !debouncedSearchText.isEmpty {
            return "\(base) (\(count))"
        }
        return base
    }
}

// MARK: - Root Field List (replaces OperationSectionView)

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
                let hasPreserved = astService.hasPreservedSelections(forRoot: field.name)

                RootExpandableFieldView(
                    field: field,
                    typeRef: typeRef,
                    namedType: namedType,
                    isObject: isObject,
                    isSelected: isSelected,
                    hasPreservedSelections: hasPreserved,
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
    let hasPreservedSelections: Bool
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
                        rootTypeName: rootTypeName
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
                    hasPreservedSelections: hasPreservedSelections,
                    showTypes: showTypes,
                    inspectableField: field
                )
                .onTapGesture {
                    handleRootTap()
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
                hasPreservedSelections: hasPreservedSelections,
                showTypes: showTypes,
                inspectableField: field
            )
            .onTapGesture {
                handleRootTap()
            }
        }
    }

    private var rootExpandedBinding: Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(field.name) },
            set: { newValue in
                if newValue {
                    expandedPaths.insert(field.name)
                } else {
                    expandedPaths.remove(field.name)
                    // When collapsing a selected root, preserve selections
                    if isSelected {
                        astService.preserveSelections(forRoot: field.name)
                        // Remove the operation from the query
                        toggleAction?.toggle(field.name, [], rootTypeName)
                    }
                }
            }
        )
    }

    private func handleRootTap() {
        guard !isDisabled else { return }

        if isSelected {
            // Deselect: preserve selections and collapse
            astService.preserveSelections(forRoot: field.name)
            toggleAction?.toggle(field.name, [], rootTypeName)
            expandedPaths.remove(field.name)
        } else {
            // Select: check for preserved selections to restore
            if let preserved = astService.restoreSelections(forRoot: field.name) {
                // Restore by toggling the root on, then re-adding child fields
                toggleAction?.toggle(field.name, [], rootTypeName)
                // Re-add each preserved child field
                guard let tab = activeTab else { return }
                let rootPrefix = field.name + "/"
                for path in preserved.sorted() where path.hasPrefix(rootPrefix) {
                    let components = path.split(separator: "/").map(String.init)
                    if components.count >= 2 {
                        let fieldName = components.last!
                        let parentPath = Array(components.dropLast())
                        let newQuery = astService.toggleField(
                            fieldName: fieldName,
                            parentPath: parentPath,
                            schema: schema,
                            currentQuery: tab.query,
                            rootTypeName: rootTypeName
                        )
                        tab.query = newQuery
                    }
                }
            } else {
                toggleAction?.toggle(field.name, [], rootTypeName)
            }
            expandedPaths.insert(field.name)
        }
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
                    rootTypeName: rootTypeName
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
                        setArgAction?.setArgument(fieldName, parentPath, argName, "", rootTypeName)
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
                    .font(.system(.caption2, design: .monospaced))
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
        .font(.system(.caption2, design: .monospaced))
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
            setArgAction?.setArgument(fieldName, parentPath, argName, trimmed, rootTypeName)
        }
    }
}
