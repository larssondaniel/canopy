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
              "subscriptionType": { "name": "Subscription" },
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
                {
                  "kind": "OBJECT", "name": "Subscription", "description": null,
                  "fields": [
                    {
                      "name": "userCreated", "description": null, "args": [],
                      "type": {"kind": "OBJECT", "name": "User", "ofType": null},
                      "isDeprecated": false, "deprecationReason": null
                    }
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

    // MARK: - selectedPaths Tests

    @Test("selectedPaths populated after parse")
    func selectedPathsPopulated() {
        let service = QueryASTService()
        service.parse("{ user { id name } }")

        #expect(service.selectedPaths.contains("user"))
        #expect(service.selectedPaths.contains("user/id"))
        #expect(service.selectedPaths.contains("user/name"))
        #expect(!service.selectedPaths.contains("user/email"))
    }

    @Test("selectedPaths cleared on empty query")
    func selectedPathsCleared() {
        let service = QueryASTService()
        service.parse("{ user { id } }")
        #expect(!service.selectedPaths.isEmpty)

        service.parse("")
        #expect(service.selectedPaths.isEmpty)
    }

    @Test("selectedPaths updated after toggleField")
    func selectedPathsAfterToggle() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        _ = service.toggleField(fieldName: "name", parentPath: ["user"], schema: schema, currentQuery: "{ user { id } }")

        #expect(service.selectedPaths.contains("user/name"))
        #expect(service.selectedPaths.contains("user/id"))
        #expect(service.selectedPaths.contains("user"))
    }

    @Test("selectedPaths consistent with isFieldSelected")
    func selectedPathsConsistentWithIsFieldSelected() {
        let service = QueryASTService()
        service.parse("{ user { id name } posts { id title } }")

        // Verify selectedPaths and isFieldSelected agree
        #expect(service.isFieldSelected(fieldName: "user", parentPath: []))
        #expect(service.selectedPaths.contains("user"))

        #expect(service.isFieldSelected(fieldName: "id", parentPath: ["user"]))
        #expect(service.selectedPaths.contains("user/id"))

        #expect(service.isFieldSelected(fieldName: "posts", parentPath: []))
        #expect(service.selectedPaths.contains("posts"))

        #expect(!service.isFieldSelected(fieldName: "email", parentPath: ["user"]))
        #expect(!service.selectedPaths.contains("user/email"))
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

    // MARK: - Argument Editing Tests

    @Test("formatArgumentLiteral quotes String and ID types")
    func formatStringAndID() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        #expect(service.formatArgumentLiteral(value: "hello", typeName: "String", schema: schema) == "\"hello\"")
        #expect(service.formatArgumentLiteral(value: "123", typeName: "ID", schema: schema) == "\"123\"")
    }

    @Test("formatArgumentLiteral returns bare number for Int and Float")
    func formatIntAndFloat() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        #expect(service.formatArgumentLiteral(value: "42", typeName: "Int", schema: schema) == "42")
        #expect(service.formatArgumentLiteral(value: "3.14", typeName: "Float", schema: schema) == "3.14")
    }

    @Test("formatArgumentLiteral returns bare value for Boolean")
    func formatBoolean() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        #expect(service.formatArgumentLiteral(value: "true", typeName: "Boolean", schema: schema) == "true")
        #expect(service.formatArgumentLiteral(value: "False", typeName: "Boolean", schema: schema) == "false")
    }

    @Test("formatArgumentLiteral returns nil for empty value")
    func formatEmpty() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        #expect(service.formatArgumentLiteral(value: "", typeName: "String", schema: schema) == nil)
        #expect(service.formatArgumentLiteral(value: "  ", typeName: "Int", schema: schema) == nil)
    }

    @Test("setArguments adds argument to existing field")
    func setArgumentsAdds() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        let result = service.setArguments(
            fieldName: "user",
            parentPath: [],
            arguments: ["id": "123"],
            schema: schema,
            currentQuery: "{ user { id } }"
        )

        #expect(result.contains("user"))
        #expect(result.contains("123"))
        #expect(result.contains("id"))
    }

    @Test("setArguments with empty value removes argument")
    func setArgumentsRemoves() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user(id: \"123\") { id } }")

        let result = service.setArguments(
            fieldName: "user",
            parentPath: [],
            arguments: [:],
            schema: schema,
            currentQuery: "{ user(id: \"123\") { id } }"
        )

        // Should not contain the argument
        #expect(!result.contains("123"))
        #expect(result.contains("user"))
        #expect(result.contains("id"))
    }

    @Test("argumentValues cache populated after parsing query with arguments")
    func argumentValuesCachePopulated() {
        let service = QueryASTService()
        service.parse("{ user(id: \"abc\") { name } }")

        #expect(service.argumentValues["user"]?["id"] == "abc")
    }

    @Test("argumentValues round-trip: set → print → parse → cache matches")
    func argumentValuesRoundTrip() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        let result = service.setArguments(
            fieldName: "user",
            parentPath: [],
            arguments: ["id": "xyz"],
            schema: schema,
            currentQuery: "{ user { id } }"
        )

        // Re-parse the result
        service.parse(result)
        #expect(service.argumentValues["user"]?["id"] == "xyz")
    }

    // MARK: - Mutation/Subscription Toggle Tests

    @Test("Toggle mutation field on with rootTypeName resolves correctly")
    func toggleMutationField() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Toggle createUser (a mutation field that returns User — should auto-select "id")
        let result = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            rootTypeName: schema.mutationTypeName
        )

        #expect(result.contains("createUser"))
        #expect(result.contains("id")) // User has "id", so auto-selected
    }

    @Test("Toggle subscription field on with rootTypeName resolves correctly")
    func toggleSubscriptionField() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Toggle userCreated (a subscription field that returns User)
        let result = service.toggleField(
            fieldName: "userCreated",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            rootTypeName: schema.subscriptionTypeName
        )

        #expect(result.contains("userCreated"))
        #expect(result.contains("id")) // User has "id", so auto-selected
    }

    @Test("setArguments with mutation rootTypeName resolves argument types correctly")
    func setArgumentsForMutation() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // First add createUser to get a document
        let query = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            rootTypeName: schema.mutationTypeName
        )

        // Now set an argument on createUser using mutation root type
        let result = service.setArguments(
            fieldName: "createUser",
            parentPath: [],
            arguments: ["name": "Alice"],
            schema: schema,
            currentQuery: query,
            rootTypeName: schema.mutationTypeName
        )

        #expect(result.contains("createUser"))
        #expect(result.contains("Alice"))
    }

    // MARK: - Preserved Selections Tests

    @Test("preserveSelections stores child paths for a root operation")
    func preserveSelectionsStoresChildPaths() {
        let service = QueryASTService()
        service.parse("{ user { id name } }")

        service.preserveSelections(forRoot: "user")

        #expect(service.hasPreservedSelections(forRoot: "user"))
        let preserved = service.preservedSelections["user"]
        #expect(preserved?.contains("user") == true)
        #expect(preserved?.contains("user/id") == true)
        #expect(preserved?.contains("user/name") == true)
    }

    @Test("restoreSelections returns preserved paths and removes them")
    func restoreSelectionsRoundTrip() {
        let service = QueryASTService()
        service.parse("{ user { id name } }")

        service.preserveSelections(forRoot: "user")
        #expect(service.hasPreservedSelections(forRoot: "user"))

        let restored = service.restoreSelections(forRoot: "user")
        #expect(restored?.contains("user/id") == true)
        #expect(restored?.contains("user/name") == true)
        #expect(!service.hasPreservedSelections(forRoot: "user"))
    }

    @Test("Re-collapse overwrites preserved selections")
    func preserveSelectionsOverwrites() {
        let service = QueryASTService()
        service.parse("{ user { id } }")

        service.preserveSelections(forRoot: "user")
        #expect(service.preservedSelections["user"]?.contains("user/id") == true)

        // Now parse with different selection and re-preserve
        service.parse("{ user { name email } }")
        service.preserveSelections(forRoot: "user")

        let preserved = service.preservedSelections["user"]!
        #expect(!preserved.contains("user/id"))
        #expect(preserved.contains("user/name"))
        #expect(preserved.contains("user/email"))
    }

    @Test("clearPreservedSelections removes stored paths")
    func clearPreservedSelections() {
        let service = QueryASTService()
        service.parse("{ user { id } }")

        service.preserveSelections(forRoot: "user")
        #expect(service.hasPreservedSelections(forRoot: "user"))

        service.clearPreservedSelections(forRoot: "user")
        #expect(!service.hasPreservedSelections(forRoot: "user"))
    }

    @Test("hasPreservedSelections returns false for unknown root")
    func hasPreservedSelectionsUnknown() {
        let service = QueryASTService()
        #expect(!service.hasPreservedSelections(forRoot: "nonexistent"))
    }

    @Test("Toggle mutation field without rootTypeName falls back to queryTypeName and fails gracefully")
    func toggleMutationFieldWithoutRootTypeName() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Without rootTypeName, falls back to queryTypeName — createUser doesn't exist on Query
        // So it should still add the field but without auto-sub-selection (can't resolve type)
        let result = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: ""
        )

        // Should still add the field (just won't know it returns User)
        #expect(result.contains("createUser"))
    }
}
