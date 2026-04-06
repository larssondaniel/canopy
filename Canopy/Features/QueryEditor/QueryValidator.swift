import Foundation
import GraphQL

enum QueryValidator {

    struct ValidationError {
        let message: String
        let range: NSRange
    }

    /// Validate a parsed GraphQL document against the schema.
    /// Returns errors for invalid fields, unknown arguments, and wrong argument types.
    static func validate(document: Document, schema: GraphQLSchema, source: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Collect fragment definitions for resolving fragment spreads
        var fragmentDefs: [String: FragmentDefinition] = [:]
        for definition in document.definitions {
            if let frag = definition as? FragmentDefinition {
                fragmentDefs[frag.name.value] = frag
            }
        }

        // Track which fragments are referenced via spreads to avoid double-validation
        var validatedFragments = Set<String>()

        for definition in document.definitions {
            if let op = definition as? OperationDefinition {
                guard let rootType = rootType(for: op.operation, schema: schema) else { continue }
                validateSelectionSet(
                    op.selectionSet,
                    parentType: rootType,
                    schema: schema,
                    source: source,
                    fragmentDefs: fragmentDefs,
                    validatedFragments: &validatedFragments,
                    errors: &errors
                )
            }
        }

        // Validate unreferenced fragment definitions (standalone fragments)
        for (name, frag) in fragmentDefs where !validatedFragments.contains(name) {
            let typeName = frag.typeCondition.name.value
            guard let type = schema.type(named: typeName) else { continue }
            validateSelectionSet(
                frag.selectionSet,
                parentType: type,
                schema: schema,
                source: source,
                fragmentDefs: fragmentDefs,
                validatedFragments: &validatedFragments,
                errors: &errors
            )
        }

        return errors
    }

    // MARK: - Selection Set Validation

    private static func validateSelectionSet(
        _ selectionSet: SelectionSet,
        parentType: GraphQLFullType,
        schema: GraphQLSchema,
        source: String,
        fragmentDefs: [String: FragmentDefinition],
        validatedFragments: inout Set<String>,
        errors: inout [ValidationError]
    ) {
        for selection in selectionSet.selections {
            if let field = selection as? GraphQL.Field {
                validateField(field, parentType: parentType, schema: schema, source: source, fragmentDefs: fragmentDefs, validatedFragments: &validatedFragments, errors: &errors)
            } else if let inlineFragment = selection as? InlineFragment {
                let innerType: GraphQLFullType
                if let typeCondition = inlineFragment.typeCondition {
                    let typeName = typeCondition.name.value
                    if let resolved = schema.type(named: typeName) {
                        innerType = resolved
                    } else {
                        continue
                    }
                } else {
                    innerType = parentType
                }
                validateSelectionSet(
                    inlineFragment.selectionSet,
                    parentType: innerType,
                    schema: schema,
                    source: source,
                    fragmentDefs: fragmentDefs,
                    validatedFragments: &validatedFragments,
                    errors: &errors
                )
            } else if let fragmentSpread = selection as? FragmentSpread {
                let fragName = fragmentSpread.name.value
                guard !validatedFragments.contains(fragName) else { continue }
                validatedFragments.insert(fragName)
                guard let fragDef = fragmentDefs[fragName] else { continue }
                let typeName = fragDef.typeCondition.name.value
                guard let fragType = schema.type(named: typeName) else { continue }
                validateSelectionSet(
                    fragDef.selectionSet,
                    parentType: fragType,
                    schema: schema,
                    source: source,
                    fragmentDefs: fragmentDefs,
                    validatedFragments: &validatedFragments,
                    errors: &errors
                )
            }
        }
    }

    // MARK: - Field Validation

    private static func validateField(
        _ field: GraphQL.Field,
        parentType: GraphQLFullType,
        schema: GraphQLSchema,
        source: String,
        fragmentDefs: [String: FragmentDefinition],
        validatedFragments: inout Set<String>,
        errors: inout [ValidationError]
    ) {
        let fieldName = field.name.value

        // Meta-fields valid on any object/interface/union
        if fieldName == "__typename" &&
            (parentType.kind == .object || parentType.kind == .interface || parentType.kind == .union) {
            return
        }

        // __schema and __type valid on root Query type
        if (fieldName == "__schema" || fieldName == "__type") &&
            parentType.name == schema.queryTypeName {
            return
        }

        // Check field exists on parent type
        guard let schemaField = parentType.fields?.first(where: { $0.name == fieldName }) else {
            if let range = nameRange(field.name, in: source) {
                errors.append(ValidationError(
                    message: "Field '\(fieldName)' does not exist on type '\(parentType.name)'",
                    range: range
                ))
            }
            return // Don't validate arguments on an unknown field
        }

        // Validate arguments
        for argument in field.arguments {
            validateArgument(argument, schemaField: schemaField, schema: schema, source: source, errors: &errors)
        }

        // Recurse into sub-selection
        if let subSelection = field.selectionSet {
            let returnTypeName = schemaField.type.toTypeRef().namedType
            if let returnType = schema.type(named: returnTypeName) {
                validateSelectionSet(
                    subSelection,
                    parentType: returnType,
                    schema: schema,
                    source: source,
                    fragmentDefs: fragmentDefs,
                    validatedFragments: &validatedFragments,
                    errors: &errors
                )
            }
        }
    }

    // MARK: - Argument Validation

    private static func validateArgument(
        _ argument: GraphQL.Argument,
        schemaField: GraphQLField,
        schema: GraphQLSchema,
        source: String,
        errors: inout [ValidationError]
    ) {
        let argName = argument.name.value

        guard let schemaArg = schemaField.args.first(where: { $0.name == argName }) else {
            if let range = nameRange(argument.name, in: source) {
                errors.append(ValidationError(
                    message: "Unknown argument '\(argName)' on field '\(schemaField.name)'",
                    range: range
                ))
            }
            return
        }

        // Basic type checking: compare AST value kind against expected type
        validateValueType(argument.value, expectedType: schemaArg.type.toTypeRef(), schema: schema, source: source, errors: &errors)
    }

    // MARK: - Value Type Checking

    private static func validateValueType(
        _ value: Value,
        expectedType: GraphQLTypeRef,
        schema: GraphQLSchema,
        source: String,
        errors: inout [ValidationError]
    ) {
        // Unwrap NonNull for checking (a non-null expected type accepts the same values)
        let unwrapped: GraphQLTypeRef
        if case .nonNull(let inner) = expectedType {
            unwrapped = inner
        } else {
            unwrapped = expectedType
        }

        // Variables are always valid (type checking is out of scope for v1)
        if value is Variable { return }

        // Null is valid for nullable types
        if value is NullValue { return }

        // List type: check list values
        if case .list(let elementType) = unwrapped {
            if let listValue = value as? ListValue {
                for element in listValue.values {
                    validateValueType(element, expectedType: elementType, schema: schema, source: source, errors: &errors)
                }
            }
            // A single value can coerce to a list — skip
            return
        }

        let namedType = unwrapped.namedType

        // Check for enum type mismatches
        if let schemaType = schema.type(named: namedType), schemaType.kind == .enumType {
            if value is StringValue, let loc = value.loc, let range = locationRange(loc, in: source) {
                errors.append(ValidationError(
                    message: "Enum '\(namedType)' values should not be quoted",
                    range: range
                ))
            }
            return
        }

        // Basic scalar type checking
        switch namedType {
        case "String", "ID":
            if value is IntValue || value is FloatValue || value is BooleanValue {
                if let loc = value.loc, let range = locationRange(loc, in: source) {
                    errors.append(ValidationError(
                        message: "Expected type '\(expectedType.displayString)', found \(describeValue(value))",
                        range: range
                    ))
                }
            }
        case "Int":
            if value is StringValue || value is FloatValue || value is BooleanValue {
                if let loc = value.loc, let range = locationRange(loc, in: source) {
                    errors.append(ValidationError(
                        message: "Expected type '\(expectedType.displayString)', found \(describeValue(value))",
                        range: range
                    ))
                }
            }
        case "Float":
            // Int coerces to Float, so only flag strings and booleans
            if value is StringValue || value is BooleanValue {
                if let loc = value.loc, let range = locationRange(loc, in: source) {
                    errors.append(ValidationError(
                        message: "Expected type '\(expectedType.displayString)', found \(describeValue(value))",
                        range: range
                    ))
                }
            }
        case "Boolean":
            if value is StringValue || value is IntValue || value is FloatValue {
                if let loc = value.loc, let range = locationRange(loc, in: source) {
                    errors.append(ValidationError(
                        message: "Expected type '\(expectedType.displayString)', found \(describeValue(value))",
                        range: range
                    ))
                }
            }
        default:
            break // Unknown scalar or input object — skip
        }
    }

    // MARK: - Helpers

    private static func rootType(for operation: OperationType, schema: GraphQLSchema) -> GraphQLFullType? {
        let typeName: String?
        switch operation {
        case .query: typeName = schema.queryTypeName
        case .mutation: typeName = schema.mutationTypeName
        case .subscription: typeName = schema.subscriptionTypeName
        }
        guard let typeName else { return nil }
        return schema.type(named: typeName)
    }

    private static func nameRange(_ name: Name, in source: String) -> NSRange? {
        guard let loc = name.loc else { return nil }
        return locationRange(loc, in: source)
    }

    private static func locationRange(_ loc: Location, in source: String) -> NSRange? {
        let start = loc.start
        let end = loc.end
        guard start >= 0, end >= start, end <= source.count else { return nil }
        let startIndex = source.index(source.startIndex, offsetBy: start)
        let endIndex = source.index(source.startIndex, offsetBy: end)
        return NSRange(startIndex..<endIndex, in: source)
    }

    private static func describeValue(_ value: Value) -> String {
        if let sv = value as? StringValue { return "\"\(sv.value)\"" }
        if let iv = value as? IntValue { return iv.value }
        if let fv = value as? FloatValue { return fv.value }
        if let bv = value as? BooleanValue { return bv.value ? "true" : "false" }
        if let ev = value as? EnumValue { return ev.value }
        return "value"
    }
}
