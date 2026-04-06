import Testing
import Foundation
@preconcurrency import GraphQL
@testable import Canopy

@Suite("QueryValidator Tests")
struct QueryValidatorTests {

    // MARK: - Test Schema Helper

    /// Build a test schema with:
    /// Query { user(id: ID!): User, posts: [Post], version: String, search(query: String): SearchResult }
    /// Mutation { createUser(name: String): User }
    /// User { id: ID!, name: String, email: String, profile: Profile }
    /// Profile { bio: String, avatar: String }
    /// Post { id: ID!, title: String, author: User }
    /// SearchResult (UNION) = User | Post
    private func makeTestSchema() -> Canopy.GraphQLSchema {
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
                  "kind": "UNION", "name": "SearchResult", "description": null,
                  "fields": null, "inputFields": null, "interfaces": null, "enumValues": null,
                  "possibleTypes": [
                    {"kind": "OBJECT", "name": "User", "ofType": null},
                    {"kind": "OBJECT", "name": "Post", "ofType": null}
                  ]
                },
                {"kind": "SCALAR", "name": "String", "description": null, "fields": null, "inputFields": null, "interfaces": null, "enumValues": null, "possibleTypes": null},
                {"kind": "SCALAR", "name": "ID", "description": null, "fields": null, "inputFields": null, "interfaces": null, "enumValues": null, "possibleTypes": null},
                {"kind": "SCALAR", "name": "Int", "description": null, "fields": null, "inputFields": null, "interfaces": null, "enumValues": null, "possibleTypes": null},
                {"kind": "SCALAR", "name": "Boolean", "description": null, "fields": null, "inputFields": null, "interfaces": null, "enumValues": null, "possibleTypes": null}
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

    private func validate(_ query: String, schema: Canopy.GraphQLSchema? = nil) throws -> [QueryValidator.ValidationError] {
        let s = schema ?? makeTestSchema()
        let document = try GraphQL.parse(source: query)
        return QueryValidator.validate(document: document, schema: s, source: query)
    }

    // MARK: - Valid Queries

    @Test("Valid query returns no errors")
    func validQueryNoErrors() throws {
        let errors = try validate("{ user(id: \"1\") { id name email } }")
        #expect(errors.isEmpty)
    }

    @Test("Valid query with nested fields returns no errors")
    func validNestedFieldsNoErrors() throws {
        let errors = try validate("{ user(id: \"1\") { id profile { bio avatar } } }")
        #expect(errors.isEmpty)
    }

    @Test("Valid mutation returns no errors")
    func validMutationNoErrors() throws {
        let errors = try validate("mutation { createUser(name: \"Dan\") { id name } }")
        #expect(errors.isEmpty)
    }

    @Test("Empty query with only whitespace parses to no definitions")
    func emptyQueryNoDefinitions() throws {
        // "{ }" is a valid document with an empty selection set
        let doc = try GraphQL.parse(source: "{ version }")
        let schema = makeTestSchema()
        let errors = QueryValidator.validate(document: doc, schema: schema, source: "{ version }")
        #expect(errors.isEmpty)
    }

    // MARK: - Unknown Fields

    @Test("Unknown field on Query type produces error")
    func unknownFieldOnQuery() throws {
        let query = "{ nonExistent { id } }"
        let errors = try validate(query)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("nonExistent"))
        #expect(errors[0].message.contains("Query"))

        // Verify the error range points to "nonExistent" in the source
        let errorText = (query as NSString).substring(with: errors[0].range)
        #expect(errorText == "nonExistent")
    }

    @Test("Unknown nested field produces error")
    func unknownNestedField() throws {
        let query = "{ user(id: \"1\") { id nonExistent } }"
        let errors = try validate(query)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("nonExistent"))
        #expect(errors[0].message.contains("User"))
    }

    @Test("Multiple unknown fields produce multiple errors")
    func multipleUnknownFields() throws {
        let query = "{ foo bar }"
        let errors = try validate(query)
        #expect(errors.count == 2)
    }

    // MARK: - Unknown Arguments

    @Test("Unknown argument on known field produces error")
    func unknownArgument() throws {
        let query = "{ user(badArg: \"test\") { id } }"
        let errors = try validate(query)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("badArg"))
        #expect(errors[0].message.contains("user"))

        let errorText = (query as NSString).substring(with: errors[0].range)
        #expect(errorText == "badArg")
    }

    @Test("Valid argument produces no error")
    func validArgument() throws {
        let errors = try validate("{ user(id: \"123\") { id } }")
        #expect(errors.isEmpty)
    }

    // MARK: - Argument Type Checking

    @Test("Wrong argument type produces error")
    func wrongArgumentType() throws {
        // user(id: ID!) — passing an integer where ID/String expected
        let query = "{ user(id: true) { id } }"
        let errors = try validate(query)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("Expected type"))
    }

    // MARK: - __typename

    @Test("__typename on object type is valid")
    func typenameOnObject() throws {
        let errors = try validate("{ user(id: \"1\") { __typename id } }")
        #expect(errors.isEmpty)
    }

    @Test("__typename on union type is valid")
    func typenameOnUnion() throws {
        let errors = try validate("{ search(query: \"test\") { __typename } }")
        #expect(errors.isEmpty)
    }

    // MARK: - Inline Fragments

    @Test("Valid inline fragment on union type produces no errors")
    func validInlineFragment() throws {
        let query = """
        {
          search(query: "test") {
            __typename
            ... on User { id name }
            ... on Post { id title }
          }
        }
        """
        let errors = try validate(query)
        #expect(errors.isEmpty)
    }

    @Test("Invalid field in inline fragment produces error")
    func invalidFieldInInlineFragment() throws {
        let query = """
        {
          search(query: "test") {
            ... on User { id nonExistent }
          }
        }
        """
        let errors = try validate(query)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("nonExistent"))
        #expect(errors[0].message.contains("User"))
    }

    // MARK: - Fragment Spreads

    @Test("Valid fragment spread produces no errors")
    func validFragmentSpread() throws {
        let query = """
        query {
          user(id: "1") { ...UserFields }
        }
        fragment UserFields on User {
          id
          name
        }
        """
        let errors = try validate(query)
        #expect(errors.isEmpty)
    }

    @Test("Invalid field in fragment definition produces error")
    func invalidFieldInFragment() throws {
        let query = """
        query {
          user(id: "1") { ...UserFields }
        }
        fragment UserFields on User {
          id
          nonExistent
        }
        """
        let errors = try validate(query)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("nonExistent"))
    }

    // MARK: - Error Range Accuracy

    @Test("Error range accurately points to the field name")
    func errorRangeAccuracy() throws {
        let query = "{ user(id: \"1\") { id badField name } }"
        let errors = try validate(query)
        #expect(errors.count == 1)

        let errorText = (query as NSString).substring(with: errors[0].range)
        #expect(errorText == "badField")
    }
}
