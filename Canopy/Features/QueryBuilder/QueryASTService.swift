import Foundation
import GraphQL
import Observation

/// Core engine for two-way sync between the Explorer and the text editor.
/// Parses query text into an AST, supports toggling fields on/off, and reprints
/// modified ASTs back to text. Uses `suppressReparse` to prevent feedback loops.
///
/// Supports multi-operation documents: users can have fields selected across
/// query, mutation, and subscription sections simultaneously. Each produces
/// a named operation (e.g. `query Query { ... }`, `mutation Mutation { ... }`).
@Observable
@MainActor
final class QueryASTService {

    /// Last successfully parsed AST (nil if query is empty/whitespace).
    private(set) var currentDocument: Document?

    /// Last parse error message (nil if valid or empty).
    private(set) var parseError: String?

    /// Feedback loop guard: set before writing to tab.query from Explorer,
    /// checked and reset in parse path to skip the re-parse.
    private var suppressReparse: Bool = false

    /// Secondary guard: content comparison to catch formatting differences.
    private var lastPrintedQuery: String?

    /// Cached set of selected field paths per operation segment.
    /// E.g. `[.queries: ["user", "user/id", "user/name"], .mutations: ["createUser", "createUser/id"]]`
    /// Rebuilt once per AST change. Views read this for O(1) selection checks.
    private(set) var selectedPaths: [OperationSegment: Set<String>] = [:]

    /// Cached argument values per operation segment.
    /// Key structure: `[segment: [fieldPath: [argName: displayValue]]]`
    private(set) var argumentValues: [OperationSegment: [String: [String: String]]] = [:]

    /// Preserved selections for collapsed root operations, per segment.
    /// When a root operation is collapsed, its child selections are saved here.
    /// When re-expanded, these are restored. Persisted to UserDefaults via ExpandStateStore.
    var preservedSelections: [OperationSegment: [String: Set<String>]] = [:]

    /// The most recently interacted operation segment (for execution).
    private(set) var activeSegment: OperationSegment?

    // MARK: - Segment / OperationType Mapping

    private func graphQLOperationType(for segment: OperationSegment) -> OperationType {
        switch segment {
        case .queries: .query
        case .mutations: .mutation
        case .subscriptions: .subscription
        }
    }

    private func segment(for operationType: OperationType) -> OperationSegment {
        switch operationType {
        case .query: .queries
        case .mutation: .mutations
        case .subscription: .subscriptions
        }
    }

    // MARK: - Operation Helpers

    private func operationKeyword(for segment: OperationSegment) -> String {
        switch segment {
        case .queries: "query"
        case .mutations: "mutation"
        case .subscriptions: "subscription"
        }
    }

    private func operationDisplayName(for segment: OperationSegment) -> String {
        switch segment {
        case .queries: "Query"
        case .mutations: "Mutation"
        case .subscriptions: "Subscription"
        }
    }

    private func operationSortOrder(for segment: OperationSegment) -> Int {
        switch segment {
        case .queries: 0
        case .mutations: 1
        case .subscriptions: 2
        }
    }

    private func operationSortOrder(for opType: OperationType) -> Int {
        operationSortOrder(for: segment(for: opType))
    }

    /// Find the index of the first operation of the given segment's type in the document.
    private func findOperationIndex(for segment: OperationSegment, in document: Document) -> Int? {
        let targetType = graphQLOperationType(for: segment)
        return document.definitions.firstIndex { def in
            guard let op = def as? OperationDefinition else { return false }
            return op.operation == targetType
        }
    }

    /// Find the correct insertion index for a new operation to maintain query -> mutation -> subscription order.
    private func insertionIndex(for segment: OperationSegment, in definitions: [Definition]) -> Int {
        let targetOrder = operationSortOrder(for: segment)
        for (i, def) in definitions.enumerated() {
            guard let op = def as? OperationDefinition else { continue }
            if operationSortOrder(for: op.operation) > targetOrder {
                return i
            }
        }
        return definitions.count
    }

    /// Remove any operation definitions that have empty selection sets.
    private func removeEmptyOperations(from document: Document) -> Document {
        let filtered = document.definitions.filter { def in
            guard let op = def as? OperationDefinition else { return true }
            return !op.selectionSet.selections.isEmpty
        }
        if filtered.count == document.definitions.count { return document }
        return document.set(value: .array(filtered), key: "definitions")
    }

    /// Ensure all operation definitions have names. Anonymous operations get default names.
    private func ensureOperationsNamed(_ document: Document) -> Document {
        var definitions = document.definitions
        var changed = false
        for (i, def) in definitions.enumerated() {
            guard let op = def as? OperationDefinition, op.name == nil else { continue }
            let seg = segment(for: op.operation)
            let keyword = operationKeyword(for: seg)
            let name = operationDisplayName(for: seg)
            // Parse a named operation to get a Name node, then graft it onto the existing operation
            if let nameDoc = try? GraphQL.parse(source: "\(keyword) \(name) { __x }"),
               let nameOp = nameDoc.definitions.first as? OperationDefinition,
               let nameNode = nameOp.name {
                let namedOp = op.set(value: .node(nameNode), key: "name")
                definitions[i] = namedOp
                changed = true
            }
        }
        if !changed { return document }
        return document.set(value: .array(definitions), key: "definitions")
    }

    /// Resolve the default root type name for a segment from the schema.
    func rootTypeName(for segment: OperationSegment, schema: GraphQLSchema) -> String? {
        switch segment {
        case .queries: schema.queryTypeName
        case .mutations: schema.mutationTypeName
        case .subscriptions: schema.subscriptionTypeName
        }
    }

    // MARK: - Preserved Selections

    /// Save the current child selections for a root operation before removing it.
    func preserveSelections(forRoot rootFieldName: String, segment: OperationSegment = .queries) {
        let paths = selectedPaths[segment] ?? []
        let prefix = rootFieldName + "/"
        let childPaths = paths.filter { $0.hasPrefix(prefix) }
        var preserved = childPaths
        if paths.contains(rootFieldName) {
            preserved.insert(rootFieldName)
        }
        if preservedSelections[segment] == nil {
            preservedSelections[segment] = [:]
        }
        preservedSelections[segment]?[rootFieldName] = preserved
    }

    /// Restore preserved selections for a root operation (non-destructive read).
    /// Preserved data is kept until overwritten by a subsequent `preserveSelections` call.
    func restoreSelections(forRoot rootFieldName: String, segment: OperationSegment = .queries) -> Set<String>? {
        preservedSelections[segment]?[rootFieldName]
    }

    /// Check if there are preserved selections for a root operation.
    func hasPreservedSelections(forRoot rootFieldName: String, segment: OperationSegment = .queries) -> Bool {
        guard let paths = preservedSelections[segment]?[rootFieldName] else { return false }
        return !paths.isEmpty
    }

    /// Clear preserved selections for a root operation.
    func clearPreservedSelections(forRoot rootFieldName: String, segment: OperationSegment = .queries) {
        preservedSelections[segment]?.removeValue(forKey: rootFieldName)
    }

    // MARK: - Root Expand / Collapse (Batched)

    /// Expand a root operation field: add the bare field to the AST and restore any
    /// preserved child selections in a single batched operation (one print, one rebuild).
    func expandRoot(
        fieldName: String,
        segment: OperationSegment,
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String?
    ) -> String {
        let resolvedRootTypeName = rootTypeName ?? self.rootTypeName(for: segment, schema: schema)
        activeSegment = segment

        // Step 1: Add the root field (bare, no default sub-selection)
        let queryAfterRoot = addField(
            fieldName: fieldName,
            parentPath: [],
            schema: schema,
            currentQuery: currentQuery,
            rootTypeName: resolvedRootTypeName,
            segment: segment
        )

        // Step 2: If we have preserved selections, batch-add them
        guard let preserved = restoreSelections(forRoot: fieldName, segment: segment) else {
            return queryAfterRoot
        }

        let rootPrefix = fieldName + "/"
        let preservedChildren = preserved.filter { $0.hasPrefix(rootPrefix) }
        guard !preservedChildren.isEmpty else { return queryAfterRoot }

        // Re-parse the document after root was added, then graft all children
        // without intermediate print/rebuild cycles.
        guard var document = currentDocument else { return queryAfterRoot }

        for path in preservedChildren.sorted() {
            let components = path.split(separator: "/").map(String.init)
            guard components.count >= 2 else { continue }
            let childField = components.last!
            let parentPath = Array(components.dropLast())

            // Parse a snippet for this child field
            guard let snippetDoc = try? GraphQL.parse(source: "{ \(childField) }"),
                  let snippetOp = snippetDoc.definitions.first as? OperationDefinition,
                  let newField = snippetOp.selectionSet.selections.first else {
                continue
            }

            // Graft into the document (no print/rebuild yet)
            if let updated = addFieldToDocument(newField, at: parentPath, in: document, segment: segment) {
                document = updated
            }
        }

        // Single print + rebuild at the end
        let result = GraphQL.print(ast: document)
        currentDocument = document
        parseError = nil
        rebuildSelectedPaths()
        suppressReparse = true
        lastPrintedQuery = result
        return result
    }

    /// Collapse a root operation field: preserve current selections and remove the field
    /// from the AST.
    func collapseRoot(
        fieldName: String,
        segment: OperationSegment,
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String?
    ) -> String {
        let resolvedRootTypeName = rootTypeName ?? self.rootTypeName(for: segment, schema: schema)
        activeSegment = segment

        // Preserve current selections before removing
        preserveSelections(forRoot: fieldName, segment: segment)

        // Remove the root field (toggleField dispatches to removeField since it's selected)
        return toggleField(
            fieldName: fieldName,
            parentPath: [],
            schema: schema,
            currentQuery: currentQuery,
            rootTypeName: resolvedRootTypeName,
            segment: segment
        )
    }

    // MARK: - Parse

    /// Parse query text into a Document AST.
    /// On success: updates `currentDocument`, clears `parseError`.
    /// On failure: keeps last valid AST, sets `parseError`.
    /// Skips parsing if `suppressReparse` flag is set (Explorer-driven change).
    /// - Returns: `true` if parsing actually occurred (editor-initiated change),
    ///   `false` if suppressed or unchanged.
    @discardableResult
    func parse(_ queryText: String) -> Bool {
        if suppressReparse {
            suppressReparse = false
            return false
        }

        if queryText == lastPrintedQuery {
            return false
        }

        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentDocument = nil
            parseError = nil
            lastPrintedQuery = nil
            rebuildSelectedPaths()
            return true
        }

        do {
            let document = try GraphQL.parse(source: queryText)
            currentDocument = document
            parseError = nil
            rebuildSelectedPaths()
            return true
        } catch {
            // Keep last valid AST, set error
            parseError = error.localizedDescription
            return false
        }
    }

    // MARK: - Field Selection State

    /// Check if a field exists at the given path in the current AST for the given segment.
    func isFieldSelected(fieldName: String, parentPath: [String], segment: OperationSegment = .queries) -> Bool {
        let path = (parentPath + [fieldName]).joined(separator: "/")
        return selectedPaths[segment]?.contains(path) ?? false
    }

    // MARK: - Selected Paths Cache

    /// Walk the AST to build per-segment sets of selected field paths and argument values.
    private func rebuildSelectedPaths() {
        guard let document = currentDocument else {
            selectedPaths = [:]
            argumentValues = [:]
            return
        }

        var allPaths: [OperationSegment: Set<String>] = [:]
        var allArgs: [OperationSegment: [String: [String: String]]] = [:]

        for definition in document.definitions {
            guard let op = definition as? OperationDefinition else { continue }
            let seg = segment(for: op.operation)
            // Use first operation of each type (skip duplicates)
            if allPaths[seg] != nil { continue }
            var paths = Set<String>()
            var argVals: [String: [String: String]] = [:]
            collectPaths(from: op.selectionSet, prefix: "", into: &paths, argValues: &argVals)
            allPaths[seg] = paths
            allArgs[seg] = argVals
        }

        selectedPaths = allPaths
        argumentValues = allArgs
    }

    private func collectPaths(
        from selectionSet: SelectionSet,
        prefix: String,
        into paths: inout Set<String>,
        argValues: inout [String: [String: String]]
    ) {
        for selection in selectionSet.selections {
            guard let field = selection as? GraphQL.Field else { continue }
            let path = prefix.isEmpty ? field.name.value : "\(prefix)/\(field.name.value)"
            paths.insert(path)

            // Extract argument values
            if !field.arguments.isEmpty {
                var args: [String: String] = [:]
                for arg in field.arguments {
                    args[arg.name.value] = extractValueString(from: arg.value)
                }
                argValues[path] = args
            }

            if let nested = field.selectionSet {
                collectPaths(from: nested, prefix: path, into: &paths, argValues: &argValues)
            }
        }
    }

    /// Extract a display string from a GraphQL AST Value node.
    private func extractValueString(from value: Value) -> String {
        if let sv = value as? StringValue {
            return sv.value
        } else if let iv = value as? IntValue {
            return iv.value
        } else if let fv = value as? FloatValue {
            return fv.value
        } else if let bv = value as? BooleanValue {
            return bv.value ? "true" : "false"
        } else if let ev = value as? EnumValue {
            return ev.value
        } else {
            return GraphQL.print(ast: value)
        }
    }

    // MARK: - Toggle Field

    /// Toggle a field on or off in the AST. Returns the new query text.
    ///
    /// When adding an object-type field, auto-adds a default sub-selection:
    /// 1. `id` if the type has it
    /// 2. Else first scalar/enum field
    /// 3. Else `__typename`
    ///
    /// When removing the last sub-field, removes the parent field entirely.
    /// When removing the last field in an operation, removes the operation definition.
    func toggleField(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String? = nil,
        segment: OperationSegment = .queries
    ) -> String {
        let resolvedRootTypeName = rootTypeName ?? self.rootTypeName(for: segment, schema: schema)
        let isSelected = isFieldSelected(fieldName: fieldName, parentPath: parentPath, segment: segment)
        activeSegment = segment

        if isSelected {
            return removeField(fieldName: fieldName, parentPath: parentPath, currentQuery: currentQuery, segment: segment)
        } else {
            return addField(fieldName: fieldName, parentPath: parentPath, schema: schema, currentQuery: currentQuery, rootTypeName: resolvedRootTypeName, segment: segment)
        }
    }

    // MARK: - Add Field

    private func addField(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String?,
        segment: OperationSegment = .queries
    ) -> String {
        // Determine the return type of the field being added
        let fieldType = resolveFieldType(fieldName: fieldName, parentPath: parentPath, schema: schema, rootTypeName: rootTypeName)

        // Build the field text — always bare field name, no default sub-selection.
        // Object-type fields are added without a selection set; the user selects sub-fields explicitly.
        let fieldSnippet = fieldName

        // Case 1: No document exists yet — create a fresh named operation
        if currentDocument == nil {
            guard parentPath.isEmpty else { return currentQuery }
            let keyword = operationKeyword(for: segment)
            let name = operationDisplayName(for: segment)
            let fullQuery = "\(keyword) \(name) { \(fieldSnippet) }"
            guard let newDoc = try? GraphQL.parse(source: fullQuery) else { return currentQuery }
            let result = GraphQL.print(ast: newDoc)
            currentDocument = newDoc
            parseError = nil
            rebuildSelectedPaths()
            suppressReparse = true
            lastPrintedQuery = result
            return result
        }

        guard let document = currentDocument else { return currentQuery }

        // Parse a simple snippet to extract the field AST node
        guard let snippetDoc = try? GraphQL.parse(source: "{ \(fieldSnippet) }"),
              let snippetOp = snippetDoc.definitions.first as? OperationDefinition,
              let newField = snippetOp.selectionSet.selections.first else {
            return currentQuery
        }

        // Case 2: Operation of this type already exists — add field to it
        if findOperationIndex(for: segment, in: document) != nil {
            guard let newDocument = addFieldToDocument(newField, at: parentPath, in: document, segment: segment) else {
                return currentQuery
            }
            let result = GraphQL.print(ast: newDocument)
            currentDocument = newDocument
            parseError = nil
            rebuildSelectedPaths()
            suppressReparse = true
            lastPrintedQuery = result
            return result
        }

        // Case 3: No operation of this type — create a new one and add to document
        guard parentPath.isEmpty else { return currentQuery }
        let keyword = operationKeyword(for: segment)
        let name = operationDisplayName(for: segment)
        let opSnippet = "\(keyword) \(name) { \(fieldSnippet) }"
        guard let opDoc = try? GraphQL.parse(source: opSnippet),
              let newOpDef = opDoc.definitions.first else { return currentQuery }

        // Ensure existing anonymous operations get names before adding a second operation
        let namedDoc = ensureOperationsNamed(document)
        var definitions = namedDoc.definitions
        let insertIdx = insertionIndex(for: segment, in: definitions)
        definitions.insert(newOpDef, at: insertIdx)
        let newDocument = namedDoc.set(value: .array(definitions), key: "definitions")

        let result = GraphQL.print(ast: newDocument)
        currentDocument = newDocument
        parseError = nil
        rebuildSelectedPaths()
        suppressReparse = true
        lastPrintedQuery = result
        return result
    }

    // MARK: - Remove Field

    private func removeField(
        fieldName: String,
        parentPath: [String],
        currentQuery: String,
        segment: OperationSegment = .queries
    ) -> String {
        guard let document = currentDocument else { return currentQuery }

        guard let newDocument = removeFieldFromDocument(fieldName, at: parentPath, in: document, segment: segment) else {
            return currentQuery
        }

        // Remove any operations that ended up with empty selection sets
        let cleanedDocument = removeEmptyOperations(from: newDocument)

        // If no definitions remain, clear everything
        if cleanedDocument.definitions.isEmpty {
            currentDocument = nil
            parseError = nil
            lastPrintedQuery = nil
            rebuildSelectedPaths()
            suppressReparse = true
            return ""
        }

        let result = GraphQL.print(ast: cleanedDocument)
        currentDocument = cleanedDocument
        parseError = nil
        rebuildSelectedPaths()
        suppressReparse = true
        lastPrintedQuery = result
        return result
    }

    // MARK: - AST Navigation

    /// Find the SelectionSet at a given path in the document for a specific segment.
    private func selectionSetAtPath(_ path: [String], in document: Document, segment: OperationSegment = .queries) -> SelectionSet? {
        guard let index = findOperationIndex(for: segment, in: document),
              let op = document.definitions[index] as? OperationDefinition else {
            return nil
        }

        var current = op.selectionSet
        for fieldName in path {
            guard let field = current.selections.first(where: { sel in
                (sel as? GraphQL.Field)?.name.value == fieldName
            }) as? GraphQL.Field,
                  let nested = field.selectionSet else {
                return nil
            }
            current = nested
        }
        return current
    }

    // MARK: - AST Modification (using set methods)

    /// Add a field (as a Selection) to the document at the given path for a specific segment.
    private func addFieldToDocument(
        _ newField: Selection,
        at parentPath: [String],
        in document: Document,
        segment: OperationSegment
    ) -> Document? {
        guard let index = findOperationIndex(for: segment, in: document),
              let op = document.definitions[index] as? OperationDefinition else {
            return nil
        }

        let newSelectionSet = modifySelectionSet(
            op.selectionSet,
            at: parentPath,
            modification: { selections in
                var updated = selections
                updated.append(newField)
                return updated
            }
        )
        guard let newSelectionSet else { return nil }

        let newOp = op.set(value: .node(newSelectionSet), key: "selectionSet")
        var definitions = document.definitions
        definitions[index] = newOp
        return document.set(value: .array(definitions), key: "definitions")
    }

    /// Remove a field by name from the document at the given path for a specific segment.
    /// If removing the last sub-field, removes the parent field too.
    private func removeFieldFromDocument(
        _ fieldName: String,
        at parentPath: [String],
        in document: Document,
        segment: OperationSegment
    ) -> Document? {
        guard let index = findOperationIndex(for: segment, in: document),
              let op = document.definitions[index] as? OperationDefinition else {
            return nil
        }

        let newSelectionSet = modifySelectionSet(
            op.selectionSet,
            at: parentPath,
            modification: { selections in
                let filtered = selections.filter { sel in
                    guard let field = sel as? GraphQL.Field else { return true }
                    return field.name.value != fieldName
                }
                return filtered
            }
        )
        guard let newSelectionSet else { return nil }

        // Check if the modification left an empty selection set at a non-root level.
        // If so, convert the parent field to a bare field (remove its selection set)
        // instead of removing the parent entirely.
        if !parentPath.isEmpty {
            if let targetSS = findSelectionSetInModified(newSelectionSet, at: parentPath),
               targetSS.selections.isEmpty {
                // Strip the selection set from the parent field, leaving it bare
                let strippedSS = stripSelectionSet(newSelectionSet, at: parentPath)
                guard let strippedSS else { return nil }
                let newOp = op.set(value: .node(strippedSS), key: "selectionSet")
                var definitions = document.definitions
                definitions[index] = newOp
                return document.set(value: .array(definitions), key: "definitions")
            }
        }

        let newOp = op.set(value: .node(newSelectionSet), key: "selectionSet")
        var definitions = document.definitions
        definitions[index] = newOp
        return document.set(value: .array(definitions), key: "definitions")
    }

    /// Recursively modify a selection set at a given path.
    /// At the target depth (empty path), applies the modification function.
    /// At intermediate depths, recursively rebuilds the tree.
    private func modifySelectionSet(
        _ selectionSet: SelectionSet,
        at path: [String],
        modification: ([Selection]) -> [Selection]
    ) -> SelectionSet? {
        if path.isEmpty {
            // Apply modification at this level
            let newSelections = modification(selectionSet.selections)
            return selectionSet.set(value: .array(newSelections), key: "selections")
        }

        let targetFieldName = path[0]
        let remainingPath = Array(path.dropFirst())

        // Find the target field and recurse
        var newSelections: [Selection] = []
        var found = false
        for selection in selectionSet.selections {
            guard let field = selection as? GraphQL.Field,
                  field.name.value == targetFieldName else {
                newSelections.append(selection)
                continue
            }

            found = true

            // If the field has no selectionSet (bare object-type field), create an empty one
            // so we can add children to it.
            let childSS: SelectionSet
            if let existing = field.selectionSet {
                childSS = existing
            } else if remainingPath.isEmpty {
                // At target depth with nil selectionSet — create an empty one to apply modification
                guard let emptyDoc = try? GraphQL.parse(source: "{ _placeholder { _empty } }"),
                      let emptyOp = emptyDoc.definitions.first as? OperationDefinition,
                      let emptyField = emptyOp.selectionSet.selections.first as? GraphQL.Field,
                      let emptyChildSS = emptyField.selectionSet else {
                    return nil
                }
                // Strip the placeholder selection to get a truly empty selection set
                childSS = emptyChildSS.set(value: .array([] as [Selection]), key: "selections")
            } else {
                // Intermediate path with nil selectionSet — can't navigate deeper
                newSelections.append(selection)
                continue
            }

            guard let modifiedChildSS = modifySelectionSet(
                childSS, at: remainingPath, modification: modification
            ) else {
                return nil
            }
            let modifiedField = field.set(value: .node(modifiedChildSS), key: "selectionSet")
            newSelections.append(modifiedField)
        }

        guard found else { return nil }
        return selectionSet.set(value: .array(newSelections), key: "selections")
    }

    /// Navigate to a selection set in a (possibly modified) tree.
    private func findSelectionSetInModified(_ selectionSet: SelectionSet, at path: [String]) -> SelectionSet? {
        var current = selectionSet
        for fieldName in path {
            guard let field = current.selections.first(where: { sel in
                (sel as? GraphQL.Field)?.name.value == fieldName
            }) as? GraphQL.Field,
                  let nested = field.selectionSet else {
                return nil
            }
            current = nested
        }
        return current
    }

    /// Remove the selectionSet from a field at the given path, leaving it as a bare field.
    private func stripSelectionSet(_ selectionSet: SelectionSet, at path: [String]) -> SelectionSet? {
        guard !path.isEmpty else { return selectionSet }

        let targetFieldName = path.last!
        let parentPath = Array(path.dropLast())

        // Navigate to the parent selection set, then rebuild with the target field stripped
        return modifySelectionSet(selectionSet, at: parentPath) { selections in
            selections.map { sel in
                guard let field = sel as? GraphQL.Field,
                      field.name.value == targetFieldName else {
                    return sel
                }
                // Parse a bare field to get a Field node without selectionSet
                guard let bareDoc = try? GraphQL.parse(source: "{ \(targetFieldName) }"),
                      let bareOp = bareDoc.definitions.first as? OperationDefinition,
                      let bareField = bareOp.selectionSet.selections.first as? GraphQL.Field else {
                    return sel
                }
                // Preserve the original field's arguments and directives on the bare field
                var result: Node = bareField
                if !field.arguments.isEmpty {
                    result = result.set(value: .array(field.arguments), key: "arguments")
                }
                if !field.directives.isEmpty {
                    result = result.set(value: .array(field.directives), key: "directives")
                }
                if let alias = field.alias {
                    result = result.set(value: .node(alias), key: "alias")
                }
                return result as! Selection
            }
        }
    }

    // MARK: - Set Arguments

    /// Format a user-entered value as a GraphQL literal based on the schema type.
    /// Returns nil for empty input (meaning: omit this argument).
    func formatArgumentLiteral(value: String, typeName: String, schema: GraphQLSchema) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Check if it's an enum type
        if let type = schema.type(named: typeName), type.kind == .enumType {
            return trimmed // Bare identifier
        }

        switch typeName {
        case "String", "ID":
            let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case "Int":
            return trimmed
        case "Float":
            return trimmed
        case "Boolean":
            return trimmed.lowercased()
        default:
            return "\"\(trimmed)\""
        }
    }

    /// Set argument values on a field in the AST. Returns the new query text.
    /// Empty values are omitted (argument removed from query).
    func setArguments(
        fieldName: String,
        parentPath: [String],
        arguments: [String: String],
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String? = nil,
        segment: OperationSegment = .queries
    ) -> String {
        guard let document = currentDocument else { return currentQuery }

        let resolvedRootTypeName = rootTypeName ?? self.rootTypeName(for: segment, schema: schema)
        activeSegment = segment

        // Resolve schema info for the field to get argument types
        let schemaArgs = resolveFieldArgs(fieldName: fieldName, parentPath: parentPath, schema: schema, rootTypeName: resolvedRootTypeName)

        // Build the argument string for the snippet
        var argParts: [String] = []
        for (argName, rawValue) in arguments {
            let argTypeName = schemaArgs[argName] ?? "String"
            if let formatted = formatArgumentLiteral(value: rawValue, typeName: argTypeName, schema: schema) {
                argParts.append("\(argName): \(formatted)")
            }
        }

        // Build a snippet to parse and extract arguments from
        let argString = argParts.isEmpty ? "" : "(\(argParts.joined(separator: ", ")))"

        // Need a valid snippet — check if field returns an object type
        let fieldType = resolveFieldType(fieldName: fieldName, parentPath: parentPath, schema: schema, rootTypeName: resolvedRootTypeName)
        let needsSubSelection = fieldType.map { hasSubFields($0, schema: schema) } ?? false
        let snippet: String
        if needsSubSelection {
            snippet = "{ \(fieldName)\(argString) { __typename } }"
        } else {
            snippet = "{ \(fieldName)\(argString) }"
        }

        // Parse snippet to extract arguments
        guard let snippetDoc = try? GraphQL.parse(source: snippet),
              let snippetOp = snippetDoc.definitions.first as? OperationDefinition,
              let snippetField = snippetOp.selectionSet.selections.first as? GraphQL.Field else {
            return currentQuery
        }

        let newArguments = snippetField.arguments

        // Modify the target field in the document
        guard let index = findOperationIndex(for: segment, in: document),
              let op = document.definitions[index] as? OperationDefinition else {
            return currentQuery
        }

        let newSelectionSet = modifyFieldInSelectionSet(
            op.selectionSet,
            fieldName: fieldName,
            at: parentPath,
            transform: { field in
                field.set(value: .array(newArguments), key: "arguments")
            }
        )
        guard let newSelectionSet else { return currentQuery }

        let newOp = op.set(value: .node(newSelectionSet), key: "selectionSet")
        var definitions = document.definitions
        definitions[index] = newOp
        let newDocument = document.set(value: .array(definitions), key: "definitions")

        let result = GraphQL.print(ast: newDocument)
        currentDocument = newDocument
        parseError = nil
        rebuildSelectedPaths()
        suppressReparse = true
        lastPrintedQuery = result
        return result
    }

    /// Modify a specific field by name at the given parent path.
    private func modifyFieldInSelectionSet(
        _ selectionSet: SelectionSet,
        fieldName: String,
        at parentPath: [String],
        transform: (GraphQL.Field) -> GraphQL.Field
    ) -> SelectionSet? {
        if parentPath.isEmpty {
            // We're at the right level — find and transform the field
            var newSelections: [Selection] = []
            var found = false
            for selection in selectionSet.selections {
                guard let field = selection as? GraphQL.Field,
                      field.name.value == fieldName else {
                    newSelections.append(selection)
                    continue
                }
                found = true
                newSelections.append(transform(field))
            }
            guard found else { return nil }
            return selectionSet.set(value: .array(newSelections), key: "selections")
        }

        // Navigate deeper
        let targetFieldName = parentPath[0]
        let remainingPath = Array(parentPath.dropFirst())

        var newSelections: [Selection] = []
        var found = false
        for selection in selectionSet.selections {
            guard let field = selection as? GraphQL.Field,
                  field.name.value == targetFieldName,
                  let childSS = field.selectionSet else {
                newSelections.append(selection)
                continue
            }
            found = true
            guard let modifiedChildSS = modifyFieldInSelectionSet(
                childSS, fieldName: fieldName, at: remainingPath, transform: transform
            ) else {
                return nil
            }
            let modifiedField = field.set(value: .node(modifiedChildSS), key: "selectionSet")
            newSelections.append(modifiedField)
        }

        guard found else { return nil }
        return selectionSet.set(value: .array(newSelections), key: "selections")
    }

    /// Resolve the argument type names for a field from the schema.
    private func resolveFieldArgs(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        rootTypeName: String?
    ) -> [String: String] {
        var currentTypeName = rootTypeName
        for pathField in parentPath {
            guard let typeName = currentTypeName,
                  let type = schema.type(named: typeName),
                  let field = type.fields?.first(where: { $0.name == pathField }) else {
                return [:]
            }
            currentTypeName = field.type.toTypeRef().namedType
        }

        guard let typeName = currentTypeName,
              let parentType = schema.type(named: typeName),
              let field = parentType.fields?.first(where: { $0.name == fieldName }) else {
            return [:]
        }

        var result: [String: String] = [:]
        for arg in field.args {
            result[arg.name] = arg.type.toTypeRef().namedType
        }
        return result
    }

    // MARK: - Schema Helpers

    /// Resolve the GraphQL type name for a field at a given path.
    private func resolveFieldType(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        rootTypeName: String?
    ) -> GraphQLFullType? {
        var currentTypeName = rootTypeName
        for pathField in parentPath {
            guard let typeName = currentTypeName,
                  let type = schema.type(named: typeName),
                  let field = type.fields?.first(where: { $0.name == pathField }) else {
                return nil
            }
            currentTypeName = field.type.toTypeRef().namedType
        }

        guard let typeName = currentTypeName,
              let parentType = schema.type(named: typeName),
              let field = parentType.fields?.first(where: { $0.name == fieldName }) else {
            return nil
        }

        let returnTypeName = field.type.toTypeRef().namedType
        return schema.type(named: returnTypeName)
    }

    /// Check if a type has sub-fields (is an object, interface, or union).
    private func hasSubFields(_ type: GraphQLFullType, schema: GraphQLSchema) -> Bool {
        switch type.kind {
        case .object, .interface:
            return (type.fields?.isEmpty == false)
        case .union:
            return true // unions need __typename at minimum
        default:
            return false
        }
    }

    /// Pick the default sub-field for an object type:
    /// 1. `id` if present, 2. first scalar/enum field, 3. `__typename`
    private func defaultSubField(for type: GraphQLFullType, schema: GraphQLSchema) -> String {
        guard let fields = type.fields, !fields.isEmpty else {
            return "__typename"
        }

        if fields.contains(where: { $0.name == "id" }) {
            return "id"
        }

        for field in fields {
            let namedType = field.type.toTypeRef().namedType
            if let resolved = schema.type(named: namedType) {
                if resolved.kind == .scalar || resolved.kind == .enumType {
                    return field.name
                }
            }
        }

        return "__typename"
    }
}
