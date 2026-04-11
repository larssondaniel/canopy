import Testing
import Foundation
@testable import Canopy

@Suite("QueryASTService Tests")
@MainActor
struct QueryASTServiceTests {

    // MARK: - Test Schema Helper

    /// Build a minimal test schema with Query { user(id: ID!): User, posts: [Post], version: String }
    /// Mutation { createUser(name: String): User }
    /// Subscription { userCreated: User }
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

    /// Helper to get selectedPaths for a specific segment (defaults to .queries)
    private func paths(_ service: QueryASTService, _ segment: OperationSegment = .queries) -> Set<String> {
        service.selectedPaths[segment] ?? []
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

    @Test("Toggle object field on: inserts bare field name without default sub-field")
    func toggleObjectFieldBareFieldName() {
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
        #expect(!result.contains("user {")) // No sub-selection added
    }

    @Test("Toggle nested object field on: inserts bare field name")
    func toggleNestedObjectFieldBareFieldName() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        let result = service.toggleField(
            fieldName: "profile",
            parentPath: ["user"],
            schema: schema,
            currentQuery: "{ user { id } }"
        )

        service.parse(result)
        #expect(result.contains("profile"))
        #expect(!result.contains("bio")) // No default sub-field auto-selected
    }

    @Test("Adding child to bare object-type field creates selection set")
    func addChildToBareField() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Add bare "user" field
        let q1 = service.toggleField(
            fieldName: "user",
            parentPath: [],
            schema: schema,
            currentQuery: ""
        )
        #expect(q1.contains("user"))
        #expect(!q1.contains("user {"))

        // Now add "id" as a child of "user"
        let q2 = service.toggleField(
            fieldName: "id",
            parentPath: ["user"],
            schema: schema,
            currentQuery: q1
        )
        #expect(q2.contains("user"))
        #expect(q2.contains("id"))
    }

    @Test("Uncheck last sub-field leaves parent as bare field")
    func uncheckLastSubFieldLeavesParentBare() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } version }")

        let result = service.toggleField(
            fieldName: "id",
            parentPath: ["user"],
            schema: schema,
            currentQuery: "{ user { id } version }"
        )

        // "user" should remain as a bare field (no selection set)
        #expect(result.contains("user"))
        #expect(!result.contains("user {")) // No braces
        #expect(!result.contains("id"))
        #expect(result.contains("version"))
    }

    @Test("Round-trip: parse -> print produces equivalent query")
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
        service.parse("{ posts { id } }")

        let result = service.toggleField(
            fieldName: "author",
            parentPath: ["posts"],
            schema: schema,
            currentQuery: "{ posts { id } }"
        )

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
        // Should produce a named query operation
        #expect(result.contains("query Query"))

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

        let qp = paths(service)
        #expect(qp.contains("user"))
        #expect(qp.contains("user/id"))
        #expect(qp.contains("user/name"))
        #expect(!qp.contains("user/email"))
    }

    @Test("selectedPaths cleared on empty query")
    func selectedPathsCleared() {
        let service = QueryASTService()
        service.parse("{ user { id } }")
        #expect(!paths(service).isEmpty)

        service.parse("")
        #expect(paths(service).isEmpty)
    }

    @Test("selectedPaths updated after toggleField")
    func selectedPathsAfterToggle() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ user { id } }")

        _ = service.toggleField(fieldName: "name", parentPath: ["user"], schema: schema, currentQuery: "{ user { id } }")

        let qp = paths(service)
        #expect(qp.contains("user/name"))
        #expect(qp.contains("user/id"))
        #expect(qp.contains("user"))
    }

    @Test("selectedPaths consistent with isFieldSelected")
    func selectedPathsConsistentWithIsFieldSelected() {
        let service = QueryASTService()
        service.parse("{ user { id name } posts { id title } }")

        let qp = paths(service)
        #expect(service.isFieldSelected(fieldName: "user", parentPath: []))
        #expect(qp.contains("user"))

        #expect(service.isFieldSelected(fieldName: "id", parentPath: ["user"]))
        #expect(qp.contains("user/id"))

        #expect(service.isFieldSelected(fieldName: "posts", parentPath: []))
        #expect(qp.contains("posts"))

        #expect(!service.isFieldSelected(fieldName: "email", parentPath: ["user"]))
        #expect(!qp.contains("user/email"))
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

        #expect(!result.contains("123"))
        #expect(result.contains("user"))
        #expect(result.contains("id"))
    }

    @Test("argumentValues cache populated after parsing query with arguments")
    func argumentValuesCachePopulated() {
        let service = QueryASTService()
        service.parse("{ user(id: \"abc\") { name } }")

        #expect(service.argumentValues[.queries]?["user"]?["id"] == "abc")
    }

    @Test("argumentValues round-trip: set -> print -> parse -> cache matches")
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
        #expect(service.argumentValues[.queries]?["user"]?["id"] == "xyz")
    }

    // MARK: - Mutation/Subscription Toggle Tests

    @Test("Toggle mutation field on with segment resolves correctly")
    func toggleMutationField() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        let result = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            segment: .mutations
        )

        #expect(result.contains("createUser"))
        #expect(!result.contains("createUser {")) // Bare field, no default sub-selection
        #expect(result.contains("mutation Mutation"))
    }

    @Test("Toggle subscription field on with segment resolves correctly")
    func toggleSubscriptionField() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        let result = service.toggleField(
            fieldName: "userCreated",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            segment: .subscriptions
        )

        #expect(result.contains("userCreated"))
        #expect(!result.contains("userCreated {")) // Bare field, no default sub-selection
        #expect(result.contains("subscription Subscription"))
    }

    @Test("setArguments with mutation segment resolves argument types correctly")
    func setArgumentsForMutation() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // First add createUser to get a document
        let query = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            segment: .mutations
        )

        // Now set an argument on createUser using mutation segment
        let result = service.setArguments(
            fieldName: "createUser",
            parentPath: [],
            arguments: ["name": "Alice"],
            schema: schema,
            currentQuery: query,
            segment: .mutations
        )

        #expect(result.contains("createUser"))
        #expect(result.contains("Alice"))
    }

    // MARK: - Multi-Operation Tests

    @Test("Adding fields across two segments produces multi-operation document")
    func multiOperationDocument() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Add a query field
        var query = service.toggleField(
            fieldName: "version",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            segment: .queries
        )
        #expect(query.contains("query Query"))

        // Now add a mutation field — should create a second operation
        query = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: query,
            segment: .mutations
        )

        #expect(query.contains("query Query"))
        #expect(query.contains("mutation Mutation"))
        #expect(query.contains("version"))
        #expect(query.contains("createUser"))

        // Verify selectedPaths are scoped correctly
        service.parse(query)
        #expect(paths(service, .queries).contains("version"))
        #expect(!paths(service, .queries).contains("createUser"))
        #expect(paths(service, .mutations).contains("createUser"))
        #expect(!paths(service, .mutations).contains("version"))
    }

    @Test("Removing last field from a segment removes that operation")
    func removeLastFieldRemovesOperation() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Create multi-operation document
        var query = service.toggleField(
            fieldName: "version",
            parentPath: [],
            schema: schema,
            currentQuery: "",
            segment: .queries
        )
        query = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: query,
            segment: .mutations
        )

        // Remove the mutation's root field (createUser)
        query = service.toggleField(
            fieldName: "createUser",
            parentPath: [],
            schema: schema,
            currentQuery: query,
            segment: .mutations
        )

        // Should remove "createUser" entirely, leaving an empty mutation operation
        // which gets cleaned up
        service.parse(query)
        #expect(paths(service, .queries).contains("version"))
        #expect(paths(service, .mutations).isEmpty)
        #expect(!query.contains("mutation"))
    }

    @Test("Parse multi-operation text produces scoped selectedPaths")
    func parseMultiOperationText() {
        let service = QueryASTService()
        service.parse("""
        query Query {
          user {
            id
          }
        }

        mutation Mutation {
          createUser {
            id
          }
        }
        """)

        #expect(paths(service, .queries).contains("user"))
        #expect(paths(service, .queries).contains("user/id"))
        #expect(paths(service, .mutations).contains("createUser"))
        #expect(paths(service, .mutations).contains("createUser/id"))
        #expect(!paths(service, .queries).contains("createUser"))
        #expect(!paths(service, .mutations).contains("user"))
    }

    @Test("Hand-typed operations with custom names map by operation type")
    func customOperationNames() {
        let service = QueryASTService()
        service.parse("""
        query GetUsers {
          user {
            id
          }
        }

        mutation CreateStuff {
          createUser {
            id
          }
        }
        """)

        // Should still map by operation type keyword, not name
        #expect(paths(service, .queries).contains("user"))
        #expect(paths(service, .mutations).contains("createUser"))
    }

    @Test("activeSegment tracks most recent interaction")
    func activeSegmentTracking() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        _ = service.toggleField(fieldName: "version", parentPath: [], schema: schema, currentQuery: "", segment: .queries)
        #expect(service.activeSegment == .queries)

        _ = service.toggleField(fieldName: "createUser", parentPath: [], schema: schema, currentQuery: "", segment: .mutations)
        #expect(service.activeSegment == .mutations)
    }

    // MARK: - Preserved Selections Tests

    @Test("preserveSelections stores child paths for a root operation")
    func preserveSelectionsStoresChildPaths() {
        let service = QueryASTService()
        service.parse("{ user { id name } }")

        service.preserveSelections(forRoot: "user")

        #expect(service.hasPreservedSelections(forRoot: "user"))
        let preserved = service.preservedSelections[.queries]?["user"]
        #expect(preserved?.contains("user") == true)
        #expect(preserved?.contains("user/id") == true)
        #expect(preserved?.contains("user/name") == true)
    }

    @Test("restoreSelections returns preserved paths without removing them")
    func restoreSelectionsNonDestructive() {
        let service = QueryASTService()
        service.parse("{ user { id name } }")

        service.preserveSelections(forRoot: "user")
        #expect(service.hasPreservedSelections(forRoot: "user"))

        let restored = service.restoreSelections(forRoot: "user")
        #expect(restored?.contains("user/id") == true)
        #expect(restored?.contains("user/name") == true)
        // Non-destructive: preserved data is still available
        #expect(service.hasPreservedSelections(forRoot: "user"))

        // Can restore again without data loss
        let restored2 = service.restoreSelections(forRoot: "user")
        #expect(restored2?.contains("user/id") == true)
    }

    @Test("Re-collapse overwrites preserved selections")
    func preserveSelectionsOverwrites() {
        let service = QueryASTService()
        service.parse("{ user { id } }")

        service.preserveSelections(forRoot: "user")
        #expect(service.preservedSelections[.queries]?["user"]?.contains("user/id") == true)

        // Now parse with different selection and re-preserve
        service.parse("{ user { name email } }")
        service.preserveSelections(forRoot: "user")

        let preserved = service.preservedSelections[.queries]!["user"]!
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

    @Test("Preserved selections scoped per segment")
    func preservedSelectionsPerSegment() {
        let service = QueryASTService()
        service.parse("""
        query Query {
          user {
            id
          }
        }

        mutation Mutation {
          createUser {
            id
          }
        }
        """)

        service.preserveSelections(forRoot: "user", segment: .queries)
        service.preserveSelections(forRoot: "createUser", segment: .mutations)

        #expect(service.hasPreservedSelections(forRoot: "user", segment: .queries))
        #expect(!service.hasPreservedSelections(forRoot: "user", segment: .mutations))
        #expect(service.hasPreservedSelections(forRoot: "createUser", segment: .mutations))
    }

    @Test("Toggle mutation field without segment falls back to queryTypeName and fails gracefully")
    func toggleMutationFieldWithoutSegment() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Without segment, defaults to .queries — createUser doesn't exist on Query
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

    // MARK: - parse() Return Value Tests

    @Test("parse returns true for editor-initiated parse")
    func parseReturnsTrueForEditorParse() {
        let service = QueryASTService()
        let didParse = service.parse("{ user { id } }")
        #expect(didParse == true)
        #expect(service.currentDocument != nil)
    }

    @Test("parse returns true for empty/whitespace text (clears state)")
    func parseReturnsTrueForEmptyText() {
        let service = QueryASTService()
        service.parse("{ user { id } }")
        let didParse = service.parse("  ")
        #expect(didParse == true)
        #expect(service.currentDocument == nil)
    }

    @Test("parse returns false when suppressReparse is set")
    func parseReturnsFalseWhenSuppressed() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("{ version }")

        // toggleField sets suppressReparse internally
        let result = service.toggleField(
            fieldName: "user",
            parentPath: [],
            schema: schema,
            currentQuery: "{ version }"
        )

        let didParse = service.parse(result)
        #expect(didParse == false)
    }

    @Test("parse returns false for lastPrintedQuery match")
    func parseReturnsFalseForLastPrintedQueryMatch() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // toggleField from empty creates a query and sets lastPrintedQuery
        let result = service.toggleField(
            fieldName: "version",
            parentPath: [],
            schema: schema,
            currentQuery: ""
        )

        // First parse is suppressed (suppressReparse)
        _ = service.parse(result)

        // Second parse with same text hits lastPrintedQuery guard
        let didParse = service.parse(result)
        #expect(didParse == false)
    }

    @Test("parse returns false for invalid syntax")
    func parseReturnsFalseForInvalidSyntax() {
        let service = QueryASTService()
        let didParse = service.parse("{ invalid {{")
        #expect(didParse == false)
        #expect(service.parseError != nil)
    }

    // MARK: - expandRoot / collapseRoot Tests

    @Test("expandRoot with no preserved selections adds bare field name")
    func expandRootBareField() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        let result = service.expandRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: "",
            rootTypeName: "Query"
        )

        #expect(result.contains("user"))
        #expect(!result.contains("user {")) // Bare field, no sub-selection
    }

    @Test("expandRoot restores preserved selections in one batch")
    func expandRootRestoresPreserved() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Build a query with user { id name }
        service.parse("query Query {\n  user {\n    id\n    name\n  }\n}")

        // Collapse: preserve and remove
        let collapsed = service.collapseRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: "query Query {\n  user {\n    id\n    name\n  }\n}",
            rootTypeName: "Query"
        )
        #expect(!collapsed.contains("user"))
        #expect(service.hasPreservedSelections(forRoot: "user"))

        // Expand: should restore preserved id + name
        let expanded = service.expandRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: collapsed,
            rootTypeName: "Query"
        )

        #expect(expanded.contains("user"))
        #expect(expanded.contains("id"))
        #expect(expanded.contains("name"))
    }

    @Test("collapseRoot preserves selections and removes field")
    func collapseRootPreservesAndRemoves() {
        let service = QueryASTService()
        let schema = makeTestSchema()
        service.parse("query Query {\n  user {\n    id\n    email\n  }\n}")

        let result = service.collapseRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: "query Query {\n  user {\n    id\n    email\n  }\n}",
            rootTypeName: "Query"
        )

        #expect(!result.contains("user"))
        #expect(service.hasPreservedSelections(forRoot: "user"))
        let preserved = service.preservedSelections[.queries]?["user"]
        #expect(preserved?.contains("user/id") == true)
        #expect(preserved?.contains("user/email") == true)
    }

    @Test("Expand-then-collapse does not lose preserved selections")
    func expandCollapsePreservesData() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        // Parse user with id and name
        service.parse("query Query {\n  user {\n    id\n    name\n  }\n}")

        // Collapse: preserve selections
        let collapsed = service.collapseRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: "query Query {\n  user {\n    id\n    name\n  }\n}",
            rootTypeName: "Query"
        )

        // Expand: restore preserved
        let expanded = service.expandRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: collapsed,
            rootTypeName: "Query"
        )

        // Immediately collapse again — should preserve the restored selections (not lose them)
        let collapsed2 = service.collapseRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: expanded,
            rootTypeName: "Query"
        )

        // Preserved selections should still have id and name
        let preserved = service.preservedSelections[.queries]?["user"]
        #expect(preserved?.contains("user/id") == true)
        #expect(preserved?.contains("user/name") == true)

        // And re-expanding should still restore them
        let expanded2 = service.expandRoot(
            fieldName: "user",
            segment: .queries,
            schema: schema,
            currentQuery: collapsed2,
            rootTypeName: "Query"
        )
        #expect(expanded2.contains("id"))
        #expect(expanded2.contains("name"))
    }

    @Test("expandRoot with mutation segment works correctly")
    func expandRootMutation() {
        let service = QueryASTService()
        let schema = makeTestSchema()

        let result = service.expandRoot(
            fieldName: "createUser",
            segment: .mutations,
            schema: schema,
            currentQuery: "",
            rootTypeName: "Mutation"
        )

        #expect(result.contains("createUser"))
        #expect(result.contains("mutation Mutation"))
    }

    // MARK: - ExpandStateStore Persistence Tests

    @Test("Preserved selections round-trip through ExpandStateStore")
    func preservedSelectionsRoundTrip() {
        let testEndpoint = "http://test-\(UUID().uuidString).example.com/graphql"
        let selections: [OperationSegment: [String: Set<String>]] = [
            .queries: [
                "user": Set(["user", "user/id", "user/name"]),
                "posts": Set(["posts", "posts/id", "posts/title"])
            ],
            .mutations: [
                "createUser": Set(["createUser", "createUser/id"])
            ]
        ]

        ExpandStateStore.savePreservedSelections(selections, for: testEndpoint)
        let loaded = ExpandStateStore.loadPreservedSelections(for: testEndpoint)

        #expect(loaded[.queries]?["user"] == selections[.queries]?["user"])
        #expect(loaded[.queries]?["posts"] == selections[.queries]?["posts"])
        #expect(loaded[.mutations]?["createUser"] == selections[.mutations]?["createUser"])
        #expect(loaded[.subscriptions] == nil)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "preservedSelections_\(testEndpoint.hashValue)")
    }

    @Test("Loading preserved selections for unknown endpoint returns empty")
    func loadPreservedSelectionsUnknown() {
        let loaded = ExpandStateStore.loadPreservedSelections(for: "http://nonexistent-\(UUID().uuidString).example.com/graphql")
        #expect(loaded.isEmpty)
    }
}
