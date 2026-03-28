import Foundation

// MARK: - Introspection Response (JSON decoding)

struct IntrospectionResponse: Codable, Sendable {
    let data: IntrospectionData
}

struct IntrospectionData: Codable, Sendable {
    let __schema: GraphQLSchemaDTO
}

/// Raw decoded schema DTO — transformed into GraphQLSchema after decoding.
struct GraphQLSchemaDTO: Codable, Sendable {
    let queryType: NameRef?
    let mutationType: NameRef?
    let subscriptionType: NameRef?
    let types: [GraphQLFullType]
    let directives: [GraphQLDirectiveDTO]?

    struct NameRef: Codable, Sendable {
        let name: String
    }

    struct GraphQLDirectiveDTO: Codable, Sendable {
        let name: String
        let description: String?
        let locations: [String]
        let args: [GraphQLInputValue]?
    }
}

// MARK: - Schema (processed, used by views)

struct GraphQLSchema: Sendable {
    let queryTypeName: String?
    let mutationTypeName: String?
    let subscriptionTypeName: String?
    /// All user-defined types keyed by name for O(1) lookup
    let types: [String: GraphQLFullType]
    /// Pre-grouped and alphabetically sorted by kind
    let sortedTypesByKind: [GraphQLTypeKind: [GraphQLFullType]]

    /// Build a processed schema from the raw DTO.
    /// Filters out introspection meta-types (__) and pre-computes groupings.
    static func from(_ dto: GraphQLSchemaDTO) -> GraphQLSchema {
        let userTypes = dto.types.filter { !$0.name.hasPrefix("__") }
        let typesByName = Dictionary(uniqueKeysWithValues: userTypes.map { ($0.name, $0) })
        let grouped = Dictionary(grouping: userTypes, by: \.kind)
            .mapValues { $0.sorted(by: { $0.name < $1.name }) }

        return GraphQLSchema(
            queryTypeName: dto.queryType?.name,
            mutationTypeName: dto.mutationType?.name,
            subscriptionTypeName: dto.subscriptionType?.name,
            types: typesByName,
            sortedTypesByKind: grouped
        )
    }

    func type(named name: String) -> GraphQLFullType? {
        types[name]
    }
}

// MARK: - Type Definitions

struct GraphQLFullType: Codable, Sendable, Identifiable {
    var id: String { name }
    let kind: GraphQLTypeKind
    let name: String
    let description: String?
    let fields: [GraphQLField]?
    let inputFields: [GraphQLInputValue]?
    let interfaces: [IntrospectionTypeRef]?
    let enumValues: [GraphQLEnumValue]?
    let possibleTypes: [IntrospectionTypeRef]?
}

enum GraphQLTypeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case scalar = "SCALAR"
    case object = "OBJECT"
    case interface = "INTERFACE"
    case union = "UNION"
    case enumType = "ENUM"
    case inputObject = "INPUT_OBJECT"
    case list = "LIST"
    case nonNull = "NON_NULL"

    var displayName: String {
        switch self {
        case .scalar: "Scalars"
        case .object: "Objects"
        case .interface: "Interfaces"
        case .union: "Unions"
        case .enumType: "Enums"
        case .inputObject: "Input Types"
        case .list: "List"
        case .nonNull: "NonNull"
        }
    }

    var iconName: String {
        switch self {
        case .object: "cube.fill"
        case .inputObject: "arrow.right.square.fill"
        case .interface: "diamond.fill"
        case .union: "arrow.triangle.branch"
        case .enumType: "list.bullet"
        case .scalar: "textformat"
        case .list, .nonNull: "cube"
        }
    }

    var sortOrder: Int {
        switch self {
        case .object: 0
        case .interface: 1
        case .union: 2
        case .enumType: 3
        case .inputObject: 4
        case .scalar: 5
        case .list, .nonNull: 6
        }
    }
}

struct GraphQLField: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let args: [GraphQLInputValue]
    let type: IntrospectionTypeRef
    let isDeprecated: Bool
    let deprecationReason: String?
}

struct GraphQLInputValue: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let type: IntrospectionTypeRef
    let defaultValue: String?
}

struct GraphQLEnumValue: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let isDeprecated: Bool
    let deprecationReason: String?
}

// MARK: - Type Reference

/// Intermediate Codable type for the recursive type ref JSON.
/// Uses a class because structs cannot have recursive stored properties.
/// Converted to GraphQLTypeRef for use in views.
final class IntrospectionTypeRef: Codable, Sendable, Hashable {
    let kind: GraphQLTypeKind
    let name: String?
    let ofType: IntrospectionTypeRef?

    init(kind: GraphQLTypeKind, name: String? = nil, ofType: IntrospectionTypeRef? = nil) {
        self.kind = kind
        self.name = name
        self.ofType = ofType
    }

    static func == (lhs: IntrospectionTypeRef, rhs: IntrospectionTypeRef) -> Bool {
        lhs.kind == rhs.kind && lhs.name == rhs.name && lhs.ofType == rhs.ofType
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(name)
        hasher.combine(ofType)
    }

    /// Convert to the clean recursive enum, with a depth limit for safety.
    func toTypeRef(maxDepth: Int = 10) -> GraphQLTypeRef {
        guard maxDepth > 0 else { return .named("Unknown") }
        switch kind {
        case .nonNull:
            guard let inner = ofType?.toTypeRef(maxDepth: maxDepth - 1) else {
                return .named("Unknown")
            }
            return .nonNull(inner)
        case .list:
            guard let inner = ofType?.toTypeRef(maxDepth: maxDepth - 1) else {
                return .named("Unknown")
            }
            return .list(inner)
        default:
            return .named(name ?? "Unknown")
        }
    }
}

/// Clean recursive type reference for display in views.
/// NOT Codable — built from IntrospectionTypeRef.
indirect enum GraphQLTypeRef: Hashable, Sendable {
    case named(String)
    case list(GraphQLTypeRef)
    case nonNull(GraphQLTypeRef)

    /// Human-readable type signature, e.g. "[User!]!", "String", "Int!"
    var displayString: String {
        switch self {
        case .named(let name): name
        case .list(let inner): "[\(inner.displayString)]"
        case .nonNull(let inner): "\(inner.displayString)!"
        }
    }

    /// The leaf type name, unwrapping all LIST/NON_NULL wrappers.
    var namedType: String {
        switch self {
        case .named(let name): name
        case .list(let inner), .nonNull(let inner): inner.namedType
        }
    }
}
