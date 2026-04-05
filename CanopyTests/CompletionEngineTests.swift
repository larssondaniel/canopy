import Testing
import Foundation
@testable import Canopy

@Suite("CompletionEngine Tests")
@MainActor
struct CompletionEngineTests {

    // MARK: - Test Schema Helper

    /// Build a test schema with:
    /// Query { user(id: ID!): User, posts: [Post], version: String }
    /// Mutation { createUser(name: String): User }
    /// Subscription { userCreated: User }
    /// User { id: ID!, name: String, email: String, profile: Profile }
    /// Profile { bio: String, avatar: String }
    /// Post { id: ID!, title: String, author: User }
    /// SearchResult (UNION) = User | Post
    /// Node (INTERFACE) { id: ID! }
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
                      "name": "user", "description": "Fetch a user by ID",
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
                    },
                    {
                      "name": "oldField", "description": "Use newField instead",
                      "args": [],
                      "type": {"kind": "SCALAR", "name": "String", "ofType": null},
                      "isDeprecated": true, "deprecationReason": "Use newField instead"
                    },
                    {
                      "name": "search", "description": null,
                      "args": [{"name": "query", "description": null, "type": {"kind": "SCALAR", "name": "String", "ofType": null}, "defaultValue": null}],
                      "type": {"kind": "UNION", "name": "SearchResult", "ofType": null},
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
                {
                  "kind": "UNION", "name": "SearchResult", "description": null,
                  "fields": null, "inputFields": null, "interfaces": null, "enumValues": null,
                  "possibleTypes": [
                    {"kind": "OBJECT", "name": "User", "ofType": null},
                    {"kind": "OBJECT", "name": "Post", "ofType": null}
                  ]
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

    // MARK: - Root Context

    @Test("Empty document suggests root keywords")
    func emptyDocumentRootKeywords() {
        let schema = makeTestSchema()
        let items = CompletionEngine.completions(text: "", cursorOffset: 0, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("query"))
        #expect(labels.contains("mutation"))
        #expect(labels.contains("subscription"))
        #expect(labels.contains("fragment"))
    }

    @Test("Root keywords filter by prefix")
    func rootKeywordsFilterByPrefix() {
        let schema = makeTestSchema()
        let items = CompletionEngine.completions(text: "q", cursorOffset: 1, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("query"))
        #expect(!labels.contains("mutation"))
    }

    // MARK: - Field Context

    @Test("Field completions for root query type")
    func fieldCompletionsForRootQuery() {
        let schema = makeTestSchema()
        // "query { " — cursor after the opening brace
        let text = "query { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("user"))
        #expect(labels.contains("posts"))
        #expect(labels.contains("version"))
        #expect(labels.contains("__typename"))
    }

    @Test("Field completions for nested type (2 levels deep)")
    func fieldCompletionsNested() {
        let schema = makeTestSchema()
        let text = "query { user { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("id"))
        #expect(labels.contains("name"))
        #expect(labels.contains("email"))
        #expect(labels.contains("profile"))
        #expect(!labels.contains("user")) // user is a Query field, not User field
    }

    @Test("Field completions with prefix filtering")
    func fieldCompletionsWithPrefix() {
        let schema = makeTestSchema()
        let text = "query { us"
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("user"))
        #expect(!labels.contains("posts"))
        #expect(!labels.contains("version"))
    }

    @Test("Prefix filtering is case-insensitive")
    func prefixFilteringCaseInsensitive() {
        let schema = makeTestSchema()
        let text = "query { US"
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("user"))
    }

    @Test("Deprecated fields sort last")
    func deprecatedFieldsSortLast() {
        let schema = makeTestSchema()
        let text = "query { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let oldFieldItem = items.first { $0.label == "oldField" }
        let userItem = items.first { $0.label == "user" }
        #expect(oldFieldItem != nil)
        #expect(userItem != nil)
        #expect(oldFieldItem!.isDeprecated)
        #expect(oldFieldItem!.sortPriority > userItem!.sortPriority)
    }

    // MARK: - __typename Injection

    @Test("__typename suggested for object types")
    func typenameForObjectType() {
        let schema = makeTestSchema()
        let text = "query { user { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("__typename"))
    }

    @Test("Union type only suggests __typename")
    func unionTypeOnlyTypename() {
        let schema = makeTestSchema()
        // SearchResult is a union type — cursor inside search { }
        let text = "query { search { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("__typename"))
        #expect(labels.count == 1)
    }

    // MARK: - Argument Context

    @Test("Argument completions inside parentheses")
    func argumentCompletions() {
        let schema = makeTestSchema()
        let text = "query { user("
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("id"))
        #expect(items.first { $0.label == "id" }?.kind == .argument)
        #expect(items.first { $0.label == "id" }?.detail == "ID!")
    }

    // MARK: - Anonymous Query

    @Test("Anonymous query (no keyword) resolves to query type")
    func anonymousQuery() {
        let schema = makeTestSchema()
        let text = "{ "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("user"))
        #expect(labels.contains("posts"))
    }

    // MARK: - Mutation/Subscription

    @Test("Mutation root type resolution via brace scan")
    func mutationBraceScan() {
        let schema = makeTestSchema()
        let text = "mutation { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("createUser"))
        #expect(!labels.contains("user")) // user is on Query, not Mutation
    }

    @Test("Subscription root type resolution via brace scan")
    func subscriptionBraceScan() {
        let schema = makeTestSchema()
        let text = "subscription { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("userCreated"))
    }

    // MARK: - Comment/String Suppression

    @Test("Cursor inside comment suppresses completions")
    func cursorInsideComment() {
        let schema = makeTestSchema()
        let text = "query { # us"
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        #expect(items.isEmpty)
    }

    @Test("Cursor inside string suppresses completions")
    func cursorInsideString() {
        let schema = makeTestSchema()
        let text = "query { user(id: \"abc"
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        #expect(items.isEmpty)
    }

    // MARK: - No Schema

    @Test("No schema returns empty results")
    func noSchema() {
        let items = CompletionEngine.completions(text: "query { ", cursorOffset: 8, schema: nil, document: nil)
        #expect(items.isEmpty)
    }

    // MARK: - Prefix Extraction

    @Test("Extract prefix at cursor")
    func extractPrefix() {
        #expect(CompletionEngine.extractPrefix(text: "query { us", cursorOffset: 10) == "us")
        #expect(CompletionEngine.extractPrefix(text: "query { ", cursorOffset: 8) == "")
        #expect(CompletionEngine.extractPrefix(text: "", cursorOffset: 0) == "")
        #expect(CompletionEngine.extractPrefix(text: "query", cursorOffset: 5) == "query")
    }

    // MARK: - Brace-Scan Fallback

    @Test("Brace scan works on broken document")
    func braceScanFallback() {
        let schema = makeTestSchema()
        // Intentionally broken — missing closing braces
        let text = "query { user { na"
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let labels = items.map(\.label)
        #expect(labels.contains("name"))
    }

    // MARK: - Field Detail

    @Test("Field items include type display string")
    func fieldItemsIncludeTypeDisplay() {
        let schema = makeTestSchema()
        let text = "query { "
        let items = CompletionEngine.completions(text: text, cursorOffset: text.count, schema: schema, document: nil)

        let userItem = items.first { $0.label == "user" }
        #expect(userItem?.detail == "User")

        let postsItem = items.first { $0.label == "posts" }
        #expect(postsItem?.detail == "[Post]")

        let versionItem = items.first { $0.label == "version" }
        #expect(versionItem?.detail == "String")
    }
}
