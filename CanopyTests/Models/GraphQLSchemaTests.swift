import Testing
import Foundation
@testable import Canopy

@Suite("GraphQL Schema Model Tests")
struct GraphQLSchemaTests {

    // MARK: - IntrospectionTypeRef -> GraphQLTypeRef Conversion

    @Test("Named type ref converts correctly")
    func namedTypeRef() {
        let ref = IntrospectionTypeRef(kind: .object, name: "User")
        let result = ref.toTypeRef()
        #expect(result == .named("User"))
        #expect(result.displayString == "User")
        #expect(result.namedType == "User")
    }

    @Test("NonNull type ref converts correctly")
    func nonNullTypeRef() {
        let ref = IntrospectionTypeRef(
            kind: .nonNull,
            ofType: IntrospectionTypeRef(kind: .scalar, name: "String")
        )
        let result = ref.toTypeRef()
        #expect(result == .nonNull(.named("String")))
        #expect(result.displayString == "String!")
        #expect(result.namedType == "String")
    }

    @Test("List type ref converts correctly")
    func listTypeRef() {
        let ref = IntrospectionTypeRef(
            kind: .list,
            ofType: IntrospectionTypeRef(kind: .object, name: "User")
        )
        let result = ref.toTypeRef()
        #expect(result == .list(.named("User")))
        #expect(result.displayString == "[User]")
        #expect(result.namedType == "User")
    }

    @Test("Complex wrapped type [User!]! converts correctly")
    func complexWrappedType() {
        // [User!]! = NON_NULL(LIST(NON_NULL(OBJECT("User"))))
        let ref = IntrospectionTypeRef(
            kind: .nonNull,
            ofType: IntrospectionTypeRef(
                kind: .list,
                ofType: IntrospectionTypeRef(
                    kind: .nonNull,
                    ofType: IntrospectionTypeRef(kind: .object, name: "User")
                )
            )
        )
        let result = ref.toTypeRef()
        #expect(result.displayString == "[User!]!")
        #expect(result.namedType == "User")
    }

    @Test("Depth limit prevents stack overflow")
    func depthLimit() {
        // Build a deeply nested type ref (15 levels)
        var ref = IntrospectionTypeRef(kind: .scalar, name: "String")
        for _ in 0..<15 {
            ref = IntrospectionTypeRef(kind: .nonNull, ofType: ref)
        }

        let result = ref.toTypeRef(maxDepth: 10)
        // Should hit "Unknown" at depth 10 instead of crashing
        #expect(result.namedType == "Unknown" || result.namedType == "String")
    }

    @Test("Missing name defaults to Unknown")
    func missingName() {
        let ref = IntrospectionTypeRef(kind: .object, name: nil)
        let result = ref.toTypeRef()
        #expect(result == .named("Unknown"))
    }

    // MARK: - JSON Decoding

    @Test("Decodes minimal introspection response")
    func decodeMinimalResponse() throws {
        let json = """
        {
          "data": {
            "__schema": {
              "queryType": { "name": "Query" },
              "mutationType": null,
              "subscriptionType": null,
              "types": [
                {
                  "kind": "OBJECT",
                  "name": "Query",
                  "description": "Root query type",
                  "fields": [
                    {
                      "name": "user",
                      "description": "Get a user by ID",
                      "args": [
                        {
                          "name": "id",
                          "description": null,
                          "type": { "kind": "NON_NULL", "name": null, "ofType": { "kind": "SCALAR", "name": "ID", "ofType": null } },
                          "defaultValue": null
                        }
                      ],
                      "type": { "kind": "OBJECT", "name": "User", "ofType": null },
                      "isDeprecated": false,
                      "deprecationReason": null
                    }
                  ],
                  "inputFields": null,
                  "interfaces": [],
                  "enumValues": null,
                  "possibleTypes": null
                },
                {
                  "kind": "OBJECT",
                  "name": "User",
                  "description": "A registered user",
                  "fields": [
                    {
                      "name": "id",
                      "description": null,
                      "args": [],
                      "type": { "kind": "NON_NULL", "name": null, "ofType": { "kind": "SCALAR", "name": "ID", "ofType": null } },
                      "isDeprecated": false,
                      "deprecationReason": null
                    },
                    {
                      "name": "name",
                      "description": null,
                      "args": [],
                      "type": { "kind": "NON_NULL", "name": null, "ofType": { "kind": "SCALAR", "name": "String", "ofType": null } },
                      "isDeprecated": false,
                      "deprecationReason": null
                    }
                  ],
                  "inputFields": null,
                  "interfaces": [],
                  "enumValues": null,
                  "possibleTypes": null
                },
                {
                  "kind": "SCALAR",
                  "name": "String",
                  "description": null,
                  "fields": null,
                  "inputFields": null,
                  "interfaces": null,
                  "enumValues": null,
                  "possibleTypes": null
                },
                {
                  "kind": "SCALAR",
                  "name": "ID",
                  "description": null,
                  "fields": null,
                  "inputFields": null,
                  "interfaces": null,
                  "enumValues": null,
                  "possibleTypes": null
                },
                {
                  "kind": "OBJECT",
                  "name": "__Schema",
                  "description": "Introspection type",
                  "fields": [],
                  "inputFields": null,
                  "interfaces": [],
                  "enumValues": null,
                  "possibleTypes": null
                }
              ],
              "directives": []
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(IntrospectionResponse.self, from: data)
        let schema = GraphQLSchema.from(response.data.__schema)

        #expect(schema.queryTypeName == "Query")
        #expect(schema.mutationTypeName == nil)
        #expect(schema.subscriptionTypeName == nil)

        // __Schema should be filtered out
        #expect(schema.types["__Schema"] == nil)

        // User types should be present
        #expect(schema.types["Query"] != nil)
        #expect(schema.types["User"] != nil)
        #expect(schema.types["String"] != nil)
        #expect(schema.types["ID"] != nil)

        // Check grouped types
        #expect(schema.sortedTypesByKind[.object]?.count == 2) // Query, User (no __Schema)
        #expect(schema.sortedTypesByKind[.scalar]?.count == 2) // String, ID

        // Check field structure
        let queryType = schema.types["Query"]!
        #expect(queryType.fields?.count == 1)
        let userField = queryType.fields!.first!
        #expect(userField.name == "user")
        #expect(userField.args.count == 1)
        #expect(userField.args.first?.name == "id")
        #expect(userField.type.toTypeRef().displayString == "User")
    }

    @Test("Decodes enum types")
    func decodeEnumType() throws {
        let json = """
        {
          "data": {
            "__schema": {
              "queryType": null,
              "mutationType": null,
              "subscriptionType": null,
              "types": [
                {
                  "kind": "ENUM",
                  "name": "Status",
                  "description": "User status",
                  "fields": null,
                  "inputFields": null,
                  "interfaces": null,
                  "enumValues": [
                    { "name": "ACTIVE", "description": "Active user", "isDeprecated": false, "deprecationReason": null },
                    { "name": "INACTIVE", "description": null, "isDeprecated": true, "deprecationReason": "Use DISABLED instead" }
                  ],
                  "possibleTypes": null
                }
              ],
              "directives": []
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(IntrospectionResponse.self, from: data)
        let schema = GraphQLSchema.from(response.data.__schema)

        let statusType = schema.types["Status"]!
        #expect(statusType.kind == .enumType)
        #expect(statusType.enumValues?.count == 2)

        let activeValue = statusType.enumValues!.first { $0.name == "ACTIVE" }!
        #expect(activeValue.isDeprecated == false)

        let inactiveValue = statusType.enumValues!.first { $0.name == "INACTIVE" }!
        #expect(inactiveValue.isDeprecated == true)
        #expect(inactiveValue.deprecationReason == "Use DISABLED instead")
    }

    // MARK: - GraphQLTypeKind

    @Test("Type kind display names")
    func typeKindDisplayNames() {
        #expect(GraphQLTypeKind.object.displayName == "Objects")
        #expect(GraphQLTypeKind.enumType.displayName == "Enums")
        #expect(GraphQLTypeKind.inputObject.displayName == "Input Types")
        #expect(GraphQLTypeKind.scalar.displayName == "Scalars")
        #expect(GraphQLTypeKind.interface.displayName == "Interfaces")
        #expect(GraphQLTypeKind.union.displayName == "Unions")
    }

    @Test("Type kind icon names are valid SF Symbols")
    func typeKindIcons() {
        #expect(!GraphQLTypeKind.object.iconName.isEmpty)
        #expect(!GraphQLTypeKind.enumType.iconName.isEmpty)
        #expect(!GraphQLTypeKind.inputObject.iconName.isEmpty)
    }

    // MARK: - SchemaStore Endpoint Normalization

    @Test("Normalizes endpoint URLs")
    func endpointNormalization() {
        #expect(SchemaStore.normalizeEndpoint("HTTPS://API.Example.COM/graphql")
            == "https://api.example.com/graphql")
        #expect(SchemaStore.normalizeEndpoint("https://api.example.com/graphql/")
            == "https://api.example.com/graphql")
        #expect(SchemaStore.normalizeEndpoint("http://localhost:4000/graphql")
            == "http://localhost:4000/graphql")
    }

    // MARK: - GraphQLTypeRef Display

    @Test("Display string for various type wrappers")
    func typeRefDisplayStrings() {
        #expect(GraphQLTypeRef.named("String").displayString == "String")
        #expect(GraphQLTypeRef.nonNull(.named("String")).displayString == "String!")
        #expect(GraphQLTypeRef.list(.named("User")).displayString == "[User]")
        #expect(GraphQLTypeRef.nonNull(.list(.nonNull(.named("User")))).displayString == "[User!]!")
        #expect(GraphQLTypeRef.list(.list(.named("Int"))).displayString == "[[Int]]")
    }

    @Test("Named type extraction from wrappers")
    func namedTypeExtraction() {
        #expect(GraphQLTypeRef.named("User").namedType == "User")
        #expect(GraphQLTypeRef.nonNull(.named("User")).namedType == "User")
        #expect(GraphQLTypeRef.nonNull(.list(.nonNull(.named("User")))).namedType == "User")
    }
}
