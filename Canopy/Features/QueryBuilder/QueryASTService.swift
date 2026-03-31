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
            return
        }

        do {
            let document = try GraphQL.parse(source: queryText)
            currentDocument = document
            parseError = nil
        } catch {
            // Keep last valid AST, set error
            parseError = error.localizedDescription
        }
    }

    // MARK: - Field Selection State

    /// Check if a field exists at the given path in the current AST.
    /// Path example: ["user", "name"] checks if `user { name }` exists.
    func isFieldSelected(fieldName: String, parentPath: [String]) -> Bool {
        guard let document = currentDocument else { return false }
        guard let selectionSet = selectionSetAtPath(parentPath, in: document) else {
            return false
        }
        return selectionSet.selections.contains { sel in
            guard let field = sel as? GraphQL.Field else { return false }
            return field.name.value == fieldName
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
        currentQuery: String
    ) -> String {
        let isSelected = isFieldSelected(fieldName: fieldName, parentPath: parentPath)

        if isSelected {
            return removeField(fieldName: fieldName, parentPath: parentPath, currentQuery: currentQuery)
        } else {
            return addField(fieldName: fieldName, parentPath: parentPath, schema: schema, currentQuery: currentQuery)
        }
    }

    // MARK: - Add Field

    private func addField(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema,
        currentQuery: String
    ) -> String {
        // Determine the return type of the field being added
        let fieldType = resolveFieldType(fieldName: fieldName, parentPath: parentPath, schema: schema)

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

    // MARK: - Schema Helpers

    /// Resolve the GraphQL type name for a field at a given path.
    private func resolveFieldType(
        fieldName: String,
        parentPath: [String],
        schema: GraphQLSchema
    ) -> GraphQLFullType? {
        // Start from the root operation type
        var currentTypeName: String?
        if parentPath.isEmpty {
            // fieldName is on the root query/mutation/subscription type
            currentTypeName = schema.queryTypeName
        } else {
            // Walk the schema to find the type at parentPath
            currentTypeName = schema.queryTypeName
            for pathField in parentPath {
                guard let typeName = currentTypeName,
                      let type = schema.type(named: typeName),
                      let field = type.fields?.first(where: { $0.name == pathField }) else {
                    return nil
                }
                currentTypeName = field.type.toTypeRef().namedType
            }
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
