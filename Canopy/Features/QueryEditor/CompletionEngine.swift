import Foundation

// MARK: - Data Model

enum CompletionContext {
    case root
    case field(parentType: GraphQLFullType)
    case argument(field: GraphQLField)
    case none
}

struct CompletionItem {
    let label: String
    let detail: String?
    let insertText: String
    let kind: CompletionKind
    let isDeprecated: Bool
    let sortPriority: Int
}

enum CompletionKind {
    case field
    case argument
    case keyword
}

// MARK: - Completion Engine

enum CompletionEngine {

    /// Resolve cursor context and return filtered completion items.
    static func completions(
        text: String,
        cursorOffset: Int,
        schema: GraphQLSchema?
    ) -> [CompletionItem] {
        guard let schema else { return [] }

        let nsText = text as NSString
        guard cursorOffset >= 0, cursorOffset <= nsText.length else { return [] }

        // Suppress completions inside comments or strings
        if isInsideCommentOrString(text: text, cursorOffset: cursorOffset) {
            return []
        }

        let prefix = extractPrefix(text: text, cursorOffset: cursorOffset)
        let context = resolveContext(text: text, cursorOffset: cursorOffset, schema: schema)

        switch context {
        case .root:
            return rootKeywordItems(schema: schema, prefix: prefix)
        case .field(let parentType):
            return fieldItems(for: parentType, schema: schema, prefix: prefix)
        case .argument(let field):
            return argumentItems(for: field, prefix: prefix)
        case .none:
            return []
        }
    }

    // MARK: - Context Resolution

    static func resolveContext(
        text: String,
        cursorOffset: Int,
        schema: GraphQLSchema
    ) -> CompletionContext {
        // Use brace scanning — it handles both complete and incomplete documents
        // reliably without depending on AST source location accuracy.
        return resolveContextFromBraceScan(text: text, cursorOffset: cursorOffset, schema: schema)
    }

    // MARK: - Brace-Scan Context Resolution

    static func resolveContextFromBraceScan(
        text: String,
        cursorOffset: Int,
        schema: GraphQLSchema
    ) -> CompletionContext {
        let nsText = text as NSString
        let scanStart = max(0, cursorOffset - 10_000)

        // Pre-compute string and comment ranges so the scanner can skip them
        let nonCodeRanges = findNonCodeRanges(text: text)

        var braceDepth = 0
        var parenDepth = 0
        var fieldNames: [String] = []
        var operationKeyword: String?
        var foundOpenBrace = false
        var pos = cursorOffset - 1

        while pos >= scanStart {
            // Skip positions inside strings or comments
            if isInNonCodeRange(pos, ranges: nonCodeRanges) {
                pos -= 1
                continue
            }

            let char = Character(UnicodeScalar(nsText.character(at: pos))!)

            // Track parens
            if char == ")" { parenDepth += 1; pos -= 1; continue }
            if char == "(" {
                if parenDepth > 0 { parenDepth -= 1; pos -= 1; continue }
                // Unmatched open paren — argument context
                let fieldName = extractWordBefore(text: text, offset: pos)
                if !fieldName.isEmpty {
                    let before = nsText.substring(to: pos).trimmingCharacters(in: .whitespaces)
                    if before.hasSuffix("@\(fieldName)") { return .none }

                    let parentType = resolveTypeForFieldPath(fieldNames.reversed(), schema: schema, operationKeyword: operationKeyword)
                        ?? rootType(for: operationKeyword, schema: schema)
                    if let parentType, let field = parentType.fields?.first(where: { $0.name == fieldName }) {
                        return .argument(field: field)
                    }
                }
                return .none
            }

            // Track braces
            if char == "}" { braceDepth += 1; pos -= 1; continue }
            if char == "{" {
                if braceDepth > 0 { braceDepth -= 1; pos -= 1; continue }
                // Unmatched open brace — extract the field/keyword before it
                foundOpenBrace = true
                let textBefore = nsText.substring(to: pos)
                let name = extractFieldNameBeforeBrace(text: textBefore)
                if let name {
                    fieldNames.append(name)
                } else {
                    let keyword = extractWordBefore(text: text, offset: pos)
                    if ["query", "mutation", "subscription"].contains(keyword) {
                        operationKeyword = keyword
                    }
                }
                pos -= 1
                continue
            }

            pos -= 1
        }

        // If we found field names, resolve the type at the deepest nesting
        if !fieldNames.isEmpty {
            if let resolvedType = resolveTypeForFieldPath(fieldNames.reversed(), schema: schema, operationKeyword: operationKeyword) {
                return .field(parentType: resolvedType)
            }
        }

        // Inside an operation's root selection set
        if foundOpenBrace {
            if let rootType = rootType(for: operationKeyword, schema: schema) {
                return .field(parentType: rootType)
            }
        }

        return .root
    }

    /// Find all string and comment ranges in the text (for skipping during brace scan).
    private static func findNonCodeRanges(text: String) -> [NSRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var ranges: [NSRange] = []

        // Block strings
        let blockStringPattern = try! NSRegularExpression(pattern: #"""""[\s\S]*?""""#)
        for match in blockStringPattern.matches(in: text, range: fullRange) {
            ranges.append(match.range)
        }

        // Regular strings
        let stringPattern = try! NSRegularExpression(pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#)
        for match in stringPattern.matches(in: text, range: fullRange) {
            ranges.append(match.range)
        }

        // Comments
        let commentPattern = try! NSRegularExpression(pattern: #"#[^\n]*"#)
        for match in commentPattern.matches(in: text, range: fullRange) {
            ranges.append(match.range)
        }

        return ranges
    }

    /// Check if a character position falls inside any non-code range.
    private static func isInNonCodeRange(_ pos: Int, ranges: [NSRange]) -> Bool {
        for range in ranges {
            if pos >= range.location && pos < NSMaxRange(range) {
                return true
            }
        }
        return false
    }

    /// Extract the field name before a `{`, handling alias syntax (`alias: fieldName {`).
    private static func extractFieldNameBeforeBrace(text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Check for operation keywords at the end — these aren't field names
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard let lastWord = words.last else { return nil }
        let lastWordStr = String(lastWord)

        if ["query", "mutation", "subscription"].contains(lastWordStr) {
            return nil
        }

        // Check for alias pattern: `alias: fieldName`
        // Also handle `operationName {` and named operations `query MyQuery {`
        if let colonIndex = trimmed.lastIndex(of: ":") {
            let afterColon = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            let fieldName = String(afterColon.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
            if !fieldName.isEmpty { return fieldName }
        }

        // No alias — the last word is the field name (if it's an identifier)
        if lastWordStr.first?.isLetter == true || lastWordStr.first == "_" {
            return lastWordStr
        }

        return nil
    }

    private static func resolveTypeForFieldPath(
        _ fieldNames: [String],
        schema: GraphQLSchema,
        operationKeyword: String?
    ) -> GraphQLFullType? {
        guard let rootType = rootType(for: operationKeyword, schema: schema) else { return nil }
        return resolveTypeForPath(fieldNames, schema: schema, rootTypeName: rootType.name)
    }

    private static func rootType(for keyword: String?, schema: GraphQLSchema) -> GraphQLFullType? {
        let typeName: String?
        switch keyword {
        case "mutation": typeName = schema.mutationTypeName
        case "subscription": typeName = schema.subscriptionTypeName
        default: typeName = schema.queryTypeName // query or anonymous
        }
        guard let typeName else { return nil }
        return schema.type(named: typeName)
    }

    // MARK: - Shared Helpers

    /// Resolve the type at the end of a field path starting from a root type.
    static func resolveTypeForPath(
        _ fieldPath: [String],
        schema: GraphQLSchema,
        rootTypeName: String
    ) -> GraphQLFullType? {
        var currentTypeName = rootTypeName
        for fieldName in fieldPath {
            guard let type = schema.type(named: currentTypeName),
                  let field = type.fields?.first(where: { $0.name == fieldName }) else {
                return nil
            }
            currentTypeName = field.type.toTypeRef().namedType
        }
        return schema.type(named: currentTypeName)
    }

    /// Extract the word being typed at the cursor position (the partial prefix for filtering).
    static func extractPrefix(text: String, cursorOffset: Int) -> String {
        let nsText = text as NSString
        guard cursorOffset > 0 else { return "" }

        var start = cursorOffset
        while start > 0 {
            let charIndex = start - 1
            let char = Character(UnicodeScalar(nsText.character(at: charIndex))!)
            if char.isLetter || char.isNumber || char == "_" {
                start -= 1
            } else {
                break
            }
        }

        if start == cursorOffset { return "" }
        return nsText.substring(with: NSRange(location: start, length: cursorOffset - start))
    }

    /// Extract the word immediately before a given offset (skipping trailing whitespace).
    private static func extractWordBefore(text: String, offset: Int) -> String {
        let nsText = text as NSString
        guard offset > 0 else { return "" }

        var end = offset
        // Skip trailing whitespace
        while end > 0 {
            let char = Character(UnicodeScalar(nsText.character(at: end - 1))!)
            if char.isWhitespace { end -= 1 } else { break }
        }

        var start = end
        while start > 0 {
            let char = Character(UnicodeScalar(nsText.character(at: start - 1))!)
            if char.isLetter || char.isNumber || char == "_" {
                start -= 1
            } else {
                break
            }
        }

        if start == end { return "" }
        return nsText.substring(with: NSRange(location: start, length: end - start))
    }

    // MARK: - Comment/String Detection

    static func isInsideCommentOrString(text: String, cursorOffset: Int) -> Bool {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Check block strings first
        let blockStringPattern = try! NSRegularExpression(pattern: #"""""[\s\S]*?""""#)
        for match in blockStringPattern.matches(in: text, range: fullRange) {
            if cursorOffset > match.range.location && cursorOffset < NSMaxRange(match.range) {
                return true
            }
        }

        // Regular strings
        let stringPattern = try! NSRegularExpression(pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#)
        for match in stringPattern.matches(in: text, range: fullRange) {
            if cursorOffset > match.range.location && cursorOffset < NSMaxRange(match.range) {
                return true
            }
        }

        // Comments
        let commentPattern = try! NSRegularExpression(pattern: #"#[^\n]*"#)
        for match in commentPattern.matches(in: text, range: fullRange) {
            if cursorOffset >= match.range.location && cursorOffset <= NSMaxRange(match.range) {
                return true
            }
        }

        return false
    }

    // MARK: - Candidate Generation

    private static func rootKeywordItems(schema: GraphQLSchema, prefix: String) -> [CompletionItem] {
        var items: [CompletionItem] = []

        if schema.queryTypeName != nil {
            items.append(CompletionItem(label: "query", detail: nil, insertText: "query", kind: .keyword, isDeprecated: false, sortPriority: 0))
        }
        if schema.mutationTypeName != nil {
            items.append(CompletionItem(label: "mutation", detail: nil, insertText: "mutation", kind: .keyword, isDeprecated: false, sortPriority: 1))
        }
        if schema.subscriptionTypeName != nil {
            items.append(CompletionItem(label: "subscription", detail: nil, insertText: "subscription", kind: .keyword, isDeprecated: false, sortPriority: 2))
        }
        items.append(CompletionItem(label: "fragment", detail: nil, insertText: "fragment", kind: .keyword, isDeprecated: false, sortPriority: 3))

        return filterByPrefix(items, prefix: prefix)
    }

    private static func fieldItems(
        for parentType: GraphQLFullType,
        schema: GraphQLSchema,
        prefix: String
    ) -> [CompletionItem] {
        var items: [CompletionItem] = []

        // Add __typename for object, interface, and union types
        if parentType.kind == .object || parentType.kind == .interface || parentType.kind == .union {
            items.append(CompletionItem(
                label: "__typename",
                detail: "String!",
                insertText: "__typename",
                kind: .field,
                isDeprecated: false,
                sortPriority: 100
            ))
        }

        // For union types, only __typename is available (inline fragments are v2)
        if parentType.kind == .union {
            return filterByPrefix(items, prefix: prefix)
        }

        // Add fields from the type
        if let fields = parentType.fields {
            for field in fields {
                let typeDisplay = field.type.toTypeRef().displayString
                items.append(CompletionItem(
                    label: field.name,
                    detail: typeDisplay,
                    insertText: field.name,
                    kind: .field,
                    isDeprecated: field.isDeprecated,
                    sortPriority: field.isDeprecated ? 50 : 0
                ))
            }
        }

        return filterByPrefix(items, prefix: prefix)
    }

    private static func argumentItems(for field: GraphQLField, prefix: String) -> [CompletionItem] {
        var items: [CompletionItem] = []
        for arg in field.args {
            let typeDisplay = arg.type.toTypeRef().displayString
            items.append(CompletionItem(
                label: arg.name,
                detail: typeDisplay,
                insertText: "\(arg.name): ",
                kind: .argument,
                isDeprecated: false,
                sortPriority: 0
            ))
        }
        return filterByPrefix(items, prefix: prefix)
    }

    private static func filterByPrefix(_ items: [CompletionItem], prefix: String) -> [CompletionItem] {
        let filtered: [CompletionItem]
        if prefix.isEmpty {
            filtered = items
        } else {
            filtered = items.filter {
                $0.label.lowercased().hasPrefix(prefix.lowercased())
            }
        }
        return filtered.sorted { $0.sortPriority < $1.sortPriority }
    }
}
