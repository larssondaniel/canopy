import SwiftUI

/// Environment key for the toggle field action, used by QueryFieldRowView
/// to avoid passing closures (which defeat SwiftUI body-skip optimization).
struct ToggleFieldAction {
    let toggle: @MainActor (_ fieldName: String, _ parentPath: [String]) -> Void
}

/// Environment key for the set argument action.
struct SetArgumentAction {
    let setArgument: @MainActor (_ fieldName: String, _ parentPath: [String], _ argName: String, _ value: String) -> Void
}

extension EnvironmentValues {
    @Entry var toggleFieldAction: ToggleFieldAction? = nil
    @Entry var setArgumentAction: SetArgumentAction? = nil
}

/// Visual query builder tree showing Queries, Mutations, Subscriptions with
/// checkboxes that stay in two-way sync with the query text editor via AST manipulation.
struct QueryExplorerView: View {
    var activeTab: QueryTab?
    var astService: QueryASTService

    @SwiftUI.Environment(SchemaStore.self) private var schemaStore

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expandedPaths: Set<String> = []

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

    // MARK: - Explorer Tree

    @ViewBuilder
    private func explorerTree(schema: GraphQLSchema, endpoint: String) -> some View {
        let toggleAction = ToggleFieldAction { fieldName, parentPath in
            guard let tab = activeTab else { return }
            let newQuery = astService.toggleField(
                fieldName: fieldName,
                parentPath: parentPath,
                schema: schema,
                currentQuery: tab.query
            )
            tab.query = newQuery
        }

        let setArgAction = SetArgumentAction { fieldName, parentPath, argName, value in
            guard let tab = activeTab else { return }
            // Build full argument map: keep existing values, update the changed one
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
                currentQuery: tab.query
            )
            tab.query = newQuery
        }

        // Read @Observable properties ONCE at this level.
        // Child views receive only value types — no @Observable access during their body.
        let selectedPaths = astService.selectedPaths
        let argValues = astService.argumentValues
        let hasParseError = astService.parseError != nil
        let multipleOps = (astService.currentDocument?.definitions.count ?? 0) > 1
        let isDisabled = activeTab == nil

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

            if let queryTypeName = schema.queryTypeName,
               let queryType = schema.type(named: queryTypeName) {
                OperationSectionView(
                    title: "Queries",
                    icon: "magnifyingglass",
                    rootType: queryType,
                    schema: schema,
                    parentPath: [],
                    searchText: debouncedSearchText,
                    selectedPaths: selectedPaths,
                    argumentValues: argValues,
                    isDisabled: isDisabled,
                    expandedPaths: $expandedPaths
                )
            }

            if let mutationTypeName = schema.mutationTypeName,
               let mutationType = schema.type(named: mutationTypeName) {
                OperationSectionView(
                    title: "Mutations",
                    icon: "arrow.triangle.2.circlepath",
                    rootType: mutationType,
                    schema: schema,
                    parentPath: [],
                    searchText: debouncedSearchText,
                    selectedPaths: selectedPaths,
                    argumentValues: argValues,
                    isDisabled: isDisabled,
                    expandedPaths: $expandedPaths
                )
            }

            if let subscriptionTypeName = schema.subscriptionTypeName,
               let subscriptionType = schema.type(named: subscriptionTypeName) {
                OperationSectionView(
                    title: "Subscriptions",
                    icon: "antenna.radiowaves.left.and.right",
                    rootType: subscriptionType,
                    schema: schema,
                    parentPath: [],
                    searchText: debouncedSearchText,
                    selectedPaths: selectedPaths,
                    argumentValues: argValues,
                    isDisabled: isDisabled,
                    expandedPaths: $expandedPaths
                )
            }
        }
        .listStyle(.sidebar)
        .environment(\.toggleFieldAction, toggleAction)
        .environment(\.setArgumentAction, setArgAction)
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

// MARK: - Operation Section

private struct OperationSectionView: View {
    let title: String
    let icon: String
    let rootType: GraphQLFullType
    let schema: GraphQLSchema
    let parentPath: [String]
    let searchText: String
    let selectedPaths: Set<String>
    let argumentValues: [String: [String: String]]
    let isDisabled: Bool
    @Binding var expandedPaths: Set<String>

    var body: some View {
        let sectionID = "op-\(title)"
        let allFields = rootType.fields ?? []
        let fields = filterFields(allFields)

        if searchText.isEmpty || !fields.isEmpty {
            DisclosureGroup(isExpanded: expandedBinding(for: sectionID)) {
                FieldListView(
                    fields: fields,
                    schema: schema,
                    parentPath: parentPath,
                    selectedPaths: selectedPaths,
                    argumentValues: argumentValues,
                    isDisabled: isDisabled,
                    searchText: searchText,
                    expandedPaths: $expandedPaths
                )
            } label: {
                Label(title, systemImage: icon)
                    .fontWeight(.semibold)
            }
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

// MARK: - Field List

private struct FieldListView: View {
    let fields: [GraphQLField]
    let schema: GraphQLSchema
    let parentPath: [String]
    let selectedPaths: Set<String>
    let argumentValues: [String: [String: String]]
    let isDisabled: Bool
    let searchText: String
    @Binding var expandedPaths: Set<String>
    var ancestorTypes: Set<String> = []
    var fieldCountCap: Int = 50

    var body: some View {
        let displayedFields = Array(fields.prefix(fieldCountCap))
        ForEach(displayedFields, id: \.name) { field in
            // Pre-compute all derived values here so ExplorerFieldView
            // receives only value types and can be body-skipped by SwiftUI.
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
    // Pre-computed values (all value types)
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
    let args: [GraphQLInputValue]
    let currentArgValues: [String: String]
    let subFields: [GraphQLField]?

    // Needed for recursive child rendering
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
                parentPath: parentPath
            )
        }
    }

    @ViewBuilder
    private var expandableField: some View {
        DisclosureGroup(isExpanded: expandedBinding(for: pathKey)) {
            // Arguments with checkboxes — editable when parent field is selected
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
                    parentPath: parentPath
                )
            }

            // Sub-fields
            if let subFields {
                let filtered = filterFields(subFields)
                var newAncestors = ancestorTypes
                let _ = newAncestors.insert(returnTypeName)
                FieldListView(
                    fields: filtered,
                    schema: schema,
                    parentPath: fieldPath,
                    selectedPaths: selectedPaths,
                    argumentValues: argumentValues,
                    isDisabled: isDisabled,
                    searchText: searchText,
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
                parentPath: parentPath
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
                        // Remove the argument from the query
                        setArgAction?.setArgument(fieldName, parentPath, argName, "")
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
            // Sync local checked state with external state
            if isChecked {
                localChecked = false // external state takes over
            }
        }
        .onAppear {
            editText = currentValue
        }
    }

    private func commitValue() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != currentValue {
            setArgAction?.setArgument(fieldName, parentPath, argName, trimmed)
        }
    }
}
