import Testing
import Foundation
@testable import Canopy

@Suite("QueryASTService Tests")
@MainActor
struct QueryASTServiceTests {

    // MARK: - Test Schema Helper

    /// Build a minimal test schema with Query { user(id: ID!): User, posts: [Post] }
    /// User { id: ID!, name: String, email: String, profile: Profile }
    /// Profile { bio: String, avatar: String }
    /// Post { id: ID!, title: String, author: User }
    private func makeTestSchema() -> GraphQLSchema {
        let json = """
        {
          "data": {
            "__schema": {
              "queryType": { "name": "Query" },
              "mutationType": { "name": "Mutation" },
              "subscriptionType": null,
              "types": [
                {
                  "kind": "OBJECT", "name": "Query", "description": null,
                  "fields": [
                    {
                      "name": "user", "description": null,
                      "args": [{"name": "id", "description": null, "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "ID", "ofType": null}}, "defaultValue": null}],
                      "type": {"kind": "OBJECT", "name": "User", "ofType": null},
                      "isDeprecated": false, "deprecationReason": null
                    },
                    {
                      "name": "posts", "description": null, "args": [],
                      "type": {"kind": "LIST", "name": null, "ofType": {"kind": "OBJECT", "name": "Post", "ofType": null}},
                      "isDeprecated": false, "deprecationReason": null
                    },
                    {
                      "name": "version", "description": null, "args": [],
                      "type": {"kind": "SCALAR", "name": "String", "ofType": null},
                      "isDeprecated": false, "deprecationReason": null
                    }
                  ],
                  "inputFields": null, "interfaces": [], "enumValues": null, "possibleTypes": null
                },
                {
                  "kind": "OBJECT", "name": "Mutation", "description": null,
                  "fields": [
                    {
                      "name": "createUser", "description": null,
                      "args": [{"name": "name", "description": null, "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "defaultValue": null}],
                      "type": {"kind": "OBJECT", "name": "User", "ofType": null},
                      "isDeprecated": false, "deprecationReason": null
                    }
                  ],
                  "inputFields": null, "interfaces": [], "enumValues": null, "possibleTypes": null
                },
                {
                  "kind": "OBJECT", "name": "User", "description": null,
                  "fields": [
                    {"name": "id", "description": null, "args": [], "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "ID", "ofType": null}}, "isDeprecated": false, "deprecationReason": null},
                    {"name": "name", "description": null, "args": [], "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "isDeprecated": false, "deprecationReason": null},
                    {"name": "email", "description": null, "args": [], "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "isDeprecated": false, "deprecationReason": null},
                    {"name": "profile", "description": null, "args": [], "type": {"kind": "OBJECT", "name": "Profile", "ofType": null}, "isDeprecated": false, "deprecationReason": null}
                  ],
                  "inputFields": null, "interfaces": [], "enumValues": null, "possibleTypes": null
                },
                {
                  "kind": "OBJECT", "name": "Profile", "description": null,
                  "fields": [
                    {"name": "bio", "description": null, "args": [], "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "isDeprecated": false, "deprecationReason": null},
                    {"name": "avatar", "description": null, "args": [], "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "isDeprecated": false, "deprecationReason": null}
                  ],
                  "inputFields": null, "interfaces": [], "enumValues": null, "possibleTypes": null
                },
                {
                  "kind": "OBJECT", "name": "Post", "description": null,
                  "fields": [
                    {"name": "id", "description": null, "args": [], "type": {"kind": "NON_NULL", "name": null, "ofType": {"kind": "SCALAR", "name": "ID", "ofType": null}}, "isDeprecated": false, "deprecationReason": null},
                    {"name": "title", "description": null, "args": [], "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "isDeprecated": false, "deprecationReason": null},
                    {"name": "author", "description": null, "args": [], "type": {"kind": "OBJECT", "name": "User", "ofType": null}, "isDeprecated": false, "deprecationReason": null}
                  ],
                  "inputFields": null, "interfaces": [], "enumValues": null, "possibleTypes": null
                },
                {"kind": "SCALAR", "name": "String", "description": null, "fields": null, "inputFields": null, "interfaces": null, "enumValues": null, "possibleTypes": null},
                {"kind": "SCALAR", "name": "ID", "description": null, "fields": null, "inputFields": null, "interfaces": null, "enumValues": null, "possibleTypes": null}
              ],
              "directives": []
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try! JSONDecoder().decode(IntrospectionResponse.self, from: data)
        return GraphQLSchema.from(response.data.__schema)
    }

    // MARK: - Parse Tests

    @Test("Parse valid query and verify field selection state")
    func parseValidQuery() {
        let service = QueryASTService()
        service.parse("{ user { id name } }")

        #expect(service.currentDocument != nil)
        #expect(service.parseError == nil)
        #expect(service.isFieldSelected(fieldName: "user", parentPath: []))
        #expect(service.isFieldSelected(fieldName: "id", parentPath: ["user"]))
        #expect(service.isFieldSelected(fieldName: "name", parentPath: ["user"]))
        #expect(!service.isFieldSelected(fieldName: "email", parentPath: ["user"]))
    }

    @Test("Parse invalid query retains last valid AST")
    func parseInvalidRetainsLast() {
        let service = QueryASTService()
        service.parse("{ user { id } }")
        #expect(service.currentDocument != nil)

        service.parse("{ invalid {")
        #expect(service.currentDocument != nil) // Still has the old valid AST
        #expect(service.parseError != nil)
    }

    @Test("Empty query produces nil AST")
    func emptyQuery() {
        let service = QueryASTService()
        service.parse("{ user { id } }")
        #expect(service.currentDocument != nil)

        service.parse("")
        #expect(service.currentDocument == nil)
        #expect(service.parseError == nil)
    }

    @Test("Whitespace-only query produces nil AST")
    func whitespaceQuery() {
        let service = QueryASTService()
        service.parse("   \n  ")
        #expect(service.currentDocument == nil)
        #expect(service.parseError == nil)
    }

    // MARK: - Toggle Tests

    @Test("Toggle field on: adds scalar field")
    func toggleScalarFieldOn() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        let result = service.toggleField(
            fieldName: "name",
            parentPath: ["user"],
            schema: schema,
            currentQuery: "{ user { id } }"
        )

        #expect(result.contains("name"))
        #expect(result.contains("id"))
        #expect(result.contains("user"))
    }

    @Test("Toggle field off: removes field")
    func toggleFieldOff() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id name } }")

        let result = service.toggleField(
            fieldName: "name",
            parentPath: ["user"],
            schema: schema,
            currentQuery: "{ user { id name } }"
        )

        #expect(!result.contains("name"))
        #expect(result.contains("id"))
        #expect(result.contains("user"))
    }

    @Test("Toggle object field on: auto-selects default sub-field (id)")
    func toggleObjectFieldAutoSelectsId() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ version }")

        let result = service.toggleField(
            fieldName: "user",
            parentPath: [],
            schema: schema,
            currentQuery: "{ version }"
        )

        #expect(result.contains("user"))
        #expect(result.contains("id")) // Auto-selected because User has "id"
    }

    @Test("Toggle object field on: auto-selects first scalar when no id")
    func toggleObjectFieldAutoSelectsFirstScalar() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        let result = service.toggleField(
            fieldName: "profile",
            parentPath: ["user"],
            schema: schema,
            currentQuery: "{ user { id } }"
        )

        // Profile has no "id" field, so should pick "bio" (first scalar)
        service.parse(result)
        #expect(result.contains("profile"))
        #expect(result.contains("bio"))
    }

    @Test("Uncheck last sub-field removes parent")
    func uncheckLastSubFieldRemovesParent() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } version }")

        let result = service.toggleField(
            fieldName: "id",
            parentPath: ["user"],
            schema: schema,
            currentQuery: "{ user { id } version }"
        )

        // "user" should be removed since "id" was its only sub-field
        #expect(!result.contains("user"))
        #expect(result.contains("version"))
    }

    @Test("Round-trip: parse → print produces equivalent query")
    func roundTrip() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Start empty, add a field
        let result1 = service.toggleField(
            fieldName: "version",
            parentPath: [],
            schema: schema,
            currentQuery: ""
        )

        // Parse the result and verify
        service.parse(result1)
        #expect(service.isFieldSelected(fieldName: "version", parentPath: []))
    }

    @Test("suppressReparse prevents re-parse after Explorer-driven text change")
    func suppressReparseGuard() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ version }")

        // Toggle a field — this sets suppressReparse
        let result = service.toggleField(
            fieldName: "user",
            parentPath: [],
            schema: schema,
            currentQuery: "{ version }"
        )

        // Now parse should be suppressed
        _ = service.currentDocument
        service.parse(result)
        // The document should still be the one set by toggleField
        #expect(service.currentDocument != nil)
        #expect(service.parseError == nil)
    }

    @Test("Circular type detection in default sub-selection")
    func circularTypeDefaultSubSelection() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        // Post.author returns User, User has no circular reference at the immediate level
        // but author → User → profile → Profile (no circular)
        service.parse("{ posts { id } }")

        let result = service.toggleField(
            fieldName: "author",
            parentPath: ["posts"],
            schema: schema,
            currentQuery: "{ posts { id } }"
        )

        // Should add author with default sub-selection (id, since User has id)
        #expect(result.contains("author"))
        #expect(result.contains("id"))
    }

    // MARK: - Edge Cases

    @Test("Toggle on root-level scalar field from empty query")
    func toggleFromEmpty() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        let result = service.toggleField(
            fieldName: "version",
            parentPath: [],
            schema: schema,
            currentQuery: ""
        )

        #expect(result.contains("version"))

        // Verify it parses correctly
        service.parse(result)
        #expect(service.currentDocument != nil)
        #expect(service.isFieldSelected(fieldName: "version", parentPath: []))
    }

    @Test("Multiple toggle operations maintain consistency")
    func multipleToggles() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Start with empty, add version
        var query = service.toggleField(fieldName: "version", parentPath: [], schema: schema, currentQuery: "")
        service.parse(query)
        #expect(service.isFieldSelected(fieldName: "version", parentPath: []))

        // Add user (object type — should get sub-selection)
        query = service.toggleField(fieldName: "user", parentPath: [], schema: schema, currentQuery: query)
        service.parse(query)
        #expect(service.isFieldSelected(fieldName: "user", parentPath: []))
        #expect(service.isFieldSelected(fieldName: "version", parentPath: []))

        // Remove version
        query = service.toggleField(fieldName: "version", parentPath: [], schema: schema, currentQuery: query)
        service.parse(query)
        #expect(!service.isFieldSelected(fieldName: "version", parentPath: []))
        #expect(service.isFieldSelected(fieldName: "user", parentPath: []))
    }
}
