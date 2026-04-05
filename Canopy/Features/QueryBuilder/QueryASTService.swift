import Foundation
import GraphQL
import Observation

/// Core engine for two-way sync between the Explorer and the text editor.
/// Parses query text into an AST, supports toggling fields on/off, and reprints
/// modified ASTs back to text. Uses `suppressReparse` to prevent feedback loops.
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

    /// Cached set of selected field paths (e.g. "user", "user/id", "user/name").
    /// Rebuilt once per AST change. Views read this for O(1) selection checks
    /// instead of traversing the AST per-field per-render.
    private(set) var selectedPaths: Set<String> = []

    /// Cached argument values extracted from the AST.
    /// Key: field path (e.g. "user"), Value: [argName: displayValue].
    /// Rebuilt alongside selectedPaths on every AST change.
    private(set) var argumentValues: [String: [String: String]] = [:]

    /// Preserved selections for collapsed root operations.
    /// Key: root field name (e.g. "user"), Value: set of child paths that were selected.
    /// When a root operation is collapsed, its child selections are saved here.
    /// When re-expanded, these are restored.
    private(set) var preservedSelections: [String: Set<String>] = [:]

    // MARK: - Preserved Selections

    /// Save the current child selections for a root operation before removing it.
    /// Copies all paths under `rootFieldName` from `selectedPaths` into the preserved store.
    func preserveSelections(forRoot rootFieldName: String) {
        let prefix = rootFieldName + "/"
        let childPaths = selectedPaths.filter { $0.hasPrefix(prefix) }
        // Include the root itself so we know it was selected
        var paths = childPaths
        if selectedPaths.contains(rootFieldName) {
            paths.insert(rootFieldName)
        }
        preservedSelections[rootFieldName] = paths
    }

    /// Restore preserved selections for a root operation and remove them from the store.
    /// Returns the set of paths that were preserved, or nil if none existed.
    func restoreSelections(forRoot rootFieldName: String) -> Set<String>? {
        preservedSelections.removeValue(forKey: rootFieldName)
    }

    /// Check if there are preserved selections for a root operation.
    func hasPreservedSelections(forRoot rootFieldName: String) -> Bool {
        guard let paths = preservedSelections[rootFieldName] else { return false }
        return !paths.isEmpty
    }

    /// Clear preserved selections for a root operation (e.g. when user manually deselects).
    func clearPreservedSelections(forRoot rootFieldName: String) {
        preservedSelections.removeValue(forKey: rootFieldName)
    }

    // MARK: - Parse

    /// Parse query text into a Document AST.
    /// On success: updates `currentDocument`, clears `parseError`.
    /// On failure: keeps last valid AST, sets `parseError`.
    /// Skips parsing if `suppressReparse` flag is set (Explorer-driven change).
    func parse(_ queryText: String) {
        if suppressReparse {
            suppressReparse = false
            return
        }

        if queryText == lastPrintedQuery {
            return
        }

        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentDocument = nil
            parseError = nil
            lastPrintedQuery = nil
            rebuildSelectedPaths()
            return
        }

        do {
            let document = try GraphQL.parse(source: queryText)
            currentDocument = document
            parseError = nil
            rebuildSelectedPaths()
        } catch {
            // Keep last valid AST, set error
            parseError = error.localizedDescription
        }
    }

    // MARK: - Field Selection State

    /// Check if a field exists at the given path in the current AST.
    /// Uses the pre-computed `selectedPaths` set for O(1) lookup.
    func isFieldSelected(fieldName: String, parentPath: [String]) -> Bool {
        let path = (parentPath + [fieldName]).joined(separator: "/")
        return selectedPaths.contains(path)
    }

    // MARK: - Selected Paths Cache

    /// Walk the AST once to build the set of all selected field paths and argument values.
    private func rebuildSelectedPaths() {
        guard let document = currentDocument,
              let op = document.definitions.first as? OperationDefinition else {
            selectedPaths = []
            argumentValues = [:]
            return
        }
        var paths = Set<String>()
        var argVals: [String: [String: String]] = [:]
        collectPaths(from: op.selectionSet, prefix: "", into: &paths, argValues: &argVals)
        selectedPaths = paths
        argumentValues = argVals
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
    func toggleField(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String? = nil
    ) -> String {
        let isSelected = isFieldSelected(fieldName: fieldName, parentPath: parentPath)

        if isSelected {
            return removeField(fieldName: fieldName, parentPath: parentPath, currentQuery: currentQuery)
        } else {
            return addField(fieldName: fieldName, parentPath: parentPath, schema: schema, currentQuery: currentQuery, rootTypeName: rootTypeName ?? schema.queryTypeName)
        }
    }

    // MARK: - Add Field

    private func addField(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        currentQuery: String,
        rootTypeName: String?
    ) -> String {
        // Determine the return type of the field being added
        let fieldType = resolveFieldType(fieldName: fieldName, parentPath: parentPath, schema: schema, rootTypeName: rootTypeName)

        // Build the field snippet to parse
        let snippet: String
        if let objectType = fieldType, hasSubFields(objectType, schema: schema) {
            let defaultSub = defaultSubField(for: objectType, schema: schema)
            snippet = "{ \(fieldName) { \(defaultSub) } }"
        } else {
            snippet = "{ \(fieldName) }"
        }

        // Parse snippet to get the new Field node
        guard let snippetDoc = try? GraphQL.parse(source: snippet),
              let snippetOp = snippetDoc.definitions.first as? OperationDefinition,
              let newField = snippetOp.selectionSet.selections.first else {
            return currentQuery
        }

        // If we have no document yet, generate a fresh query
        guard let document = currentDocument else {
            let newQuery: String
            if parentPath.isEmpty {
                // Top-level field, generate anonymous operation
                newQuery = GraphQL.print(ast: snippetDoc)
            } else {
                // Shouldn't happen in practice — need a document to have a parent path
                newQuery = currentQuery
            }
            let result = newQuery
            suppressReparse = true
            lastPrintedQuery = result
            parse(result) // Update internal AST (will be skipped via suppressReparse, but let's re-parse)
            suppressReparse = false
            // Parse the new doc
            do {
                currentDocument = try GraphQL.parse(source: result)
                parseError = nil
                rebuildSelectedPaths()
            } catch {}
            suppressReparse = true
            lastPrintedQuery = result
            return result
        }

        // Rebuild the AST with the new field added
        guard let newDocument = addFieldToDocument(newField, at: parentPath, in: document) else {
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

    // MARK: - Remove Field

    private func removeField(
        fieldName: String,
        parentPath: [String],
        currentQuery: String
    ) -> String {
        guard let document = currentDocument else { return currentQuery }

        guard let newDocument = removeFieldFromDocument(fieldName, at: parentPath, in: document) else {
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

    // MARK: - AST Navigation

    /// Find the SelectionSet at a given path in the document.
    /// Empty path returns the root operation's selection set.
    private func selectionSetAtPath(_ path: [String], in document: Document) -> SelectionSet? {
        guard let op = document.definitions.first as? OperationDefinition else {
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

    /// Add a field (as a Selection) to the document at the given path.
    /// Returns a new Document with the modification, or nil on failure.
    private func addFieldToDocument(
        _ newField: Selection,
        at parentPath: [String],
        in document: Document
    ) -> Document? {
        guard let op = document.definitions.first as? OperationDefinition else {
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
        var definitions: [Definition] = [newOp]
        // Preserve other definitions (fragments, additional operations)
        if document.definitions.count > 1 {
            definitions.append(contentsOf: document.definitions.dropFirst())
        }
        return document.set(value: .array(definitions), key: "definitions")
    }

    /// Remove a field by name from the document at the given path.
    /// If removing the last sub-field, removes the parent field too.
    private func removeFieldFromDocument(
        _ fieldName: String,
        at parentPath: [String],
        in document: Document
    ) -> Document? {
        guard let op = document.definitions.first as? OperationDefinition else {
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

        // Check if the modification left an empty selection set at a non-root level
        // If so, remove the parent field
        if !parentPath.isEmpty {
            let parentOfTarget = Array(parentPath.dropLast())
            let targetFieldName = parentPath.last!
            if let targetSS = findSelectionSetInModified(newSelectionSet, at: parentPath),
               targetSS.selections.isEmpty {
                // Remove the parent field that now has empty selections
                return removeFieldFromDocument(targetFieldName, at: parentOfTarget, in: document)
            }
        }

        let newOp = op.set(value: .node(newSelectionSet), key: "selectionSet")
        var definitions: [Definition] = [newOp]
        if document.definitions.count > 1 {
            definitions.append(contentsOf: document.definitions.dropFirst())
        }
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
                  field.name.value == targetFieldName,
                  let childSS = field.selectionSet else {
                newSelections.append(selection)
                continue
            }

            found = true
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
            // Escape any embedded quotes and wrap
            let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case "Int":
            return trimmed // Bare integer
        case "Float":
            return trimmed // Bare float
        case "Boolean":
            return trimmed.lowercased() // true/false
        default:
            // Unknown scalar — try bare (works for custom scalars)
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
        rootTypeName: String? = nil
    ) -> String {
        guard let document = currentDocument else { return currentQuery }

        let resolvedRootTypeName = rootTypeName ?? schema.queryTypeName

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
        guard let op = document.definitions.first as? OperationDefinition else {
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
        var definitions: [Definition] = [newOp]
        if document.definitions.count > 1 {
            definitions.append(contentsOf: document.definitions.dropFirst())
        }
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
    /// The transform closure receives the Field and returns a modified Field.
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
    /// The `rootTypeName` parameter specifies which root type to start traversal from
    /// (e.g. the query, mutation, or subscription type name).
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
    /// The `rootTypeName` parameter specifies which root type to start traversal from
    /// (e.g. the query, mutation, or subscription type name).
    private func resolveFieldType(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        rootTypeName: String?
    ) -> GraphQLFullType? {
        // Start from the specified root operation type
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

        // 1. Prefer "id"
        if fields.contains(where: { $0.name == "id" }) {
            return "id"
        }

        // 2. First scalar or enum field
        for field in fields {
            let namedType = field.type.toTypeRef().namedType
            if let resolved = schema.type(named: namedType) {
                if resolved.kind == .scalar || resolved.kind == .enumType {
                    return field.name
                }
            }
        }

        // 3. Fallback
        return "__typename"
    }
}
