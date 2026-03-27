import Testing
import Foundation
@testable import Canopy

@Suite("GraphQLClient Tests")
struct GraphQLClientTests {
    let client = GraphQLClient()

    @Test("Invalid URL sets error on tab")
    @MainActor
    func invalidURL() async {
        let tab = QueryTab()
        tab.endpoint = "not a url"
        tab.query = "{ test }"

        await client.send(tab: tab)

        #expect(tab.error != nil)
        #expect(tab.error?.contains("Invalid URL") == true)
        #expect(tab.isLoading == false)
    }

    @Test("Empty URL sets error on tab")
    @MainActor
    func emptyURL() async {
        let tab = QueryTab()
        tab.endpoint = ""
        tab.query = "{ test }"

        await client.send(tab: tab)

        #expect(tab.error != nil)
        #expect(tab.isLoading == false)
    }

    @Test("Invalid variables JSON sets error on tab")
    @MainActor
    func invalidVariablesJSON() async {
        let tab = QueryTab()
        tab.endpoint = "https://example.com/graphql"
        tab.query = "{ test }"
        tab.variables = "{ invalid json"

        await client.send(tab: tab)

        #expect(tab.error != nil)
        #expect(tab.error?.contains("Invalid JSON") == true)
        #expect(tab.isLoading == false)
    }

    @Test("Empty variables are accepted")
    @MainActor
    func emptyVariables() async {
        let tab = QueryTab()
        tab.endpoint = "https://example.com/graphql"
        tab.query = "{ test }"
        tab.variables = ""

        // Will fail at network level, but should not fail at validation
        await client.send(tab: tab)

        // Error should be a network error, not a validation error
        if let error = tab.error {
            #expect(!error.contains("Invalid JSON"))
        }
    }

    @Test("Valid variables JSON passes validation")
    @MainActor
    func validVariablesJSON() async {
        let tab = QueryTab()
        tab.endpoint = "https://example.com/graphql"
        tab.query = "{ test }"
        tab.variables = """
        {"key": "value"}
        """

        await client.send(tab: tab)

        // Should not be a JSON validation error
        if let error = tab.error {
            #expect(!error.contains("Invalid JSON"))
        }
    }

    @Test("Whitespace-only variables are treated as empty")
    @MainActor
    func whitespaceVariables() async {
        let tab = QueryTab()
        tab.endpoint = "https://example.com/graphql"
        tab.query = "{ test }"
        tab.variables = "   \n  "

        await client.send(tab: tab)

        if let error = tab.error {
            #expect(!error.contains("Invalid JSON"))
        }
    }

    @Test("Loading state is false after send completes")
    @MainActor
    func loadingStateReset() async {
        let tab = QueryTab()
        tab.endpoint = "https://example.com/graphql"
        tab.query = "{ test }"

        await client.send(tab: tab)

        #expect(tab.isLoading == false)
    }

    // MARK: - Auth Header Tests

    @Test("No auth injects no Authorization header")
    @MainActor
    func noAuthHeader() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .none, headers: [])
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Basic auth injects correct Authorization header")
    @MainActor
    func basicAuthHeader() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .basic(username: "user", password: "pass"), headers: [])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNz")
    }

    @Test("Bearer auth injects correct Authorization header")
    @MainActor
    func bearerAuthHeader() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .bearer(token: "my-token"), headers: [])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
    }

    @Test("Bearer with empty token injects no header")
    @MainActor
    func bearerEmptyTokenNoHeader() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .bearer(token: ""), headers: [])
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("API Key injects correct custom header")
    @MainActor
    func apiKeyHeader() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .apiKey(headerName: "X-API-Key", value: "secret"), headers: [])
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "secret")
    }

    @Test("API Key with empty name injects no header")
    @MainActor
    func apiKeyEmptyNameNoHeader() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .apiKey(headerName: "", value: "secret"), headers: [])
        // Should still have default headers but no custom API key header
        #expect(request.value(forHTTPHeaderField: "") == nil)
    }

    @Test("User headers override auth headers")
    @MainActor
    func userHeadersOverrideAuth() throws {
        let url = URL(string: "https://example.com/graphql")!
        var manualHeader = HeaderEntry()
        manualHeader.key = "Authorization"
        manualHeader.value = "Custom override"
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .bearer(token: "my-token"), headers: [manualHeader])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Custom override")
    }

    @Test("Auth headers work with GET method")
    @MainActor
    func authWithGetMethod() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .get, query: "{ test }", variables: nil, auth: .bearer(token: "my-token"), headers: [])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
    }

    @Test("Auth does not override Content-Type default")
    @MainActor
    func authDoesNotOverrideContentType() throws {
        let url = URL(string: "https://example.com/graphql")!
        let request = try client.buildRequest(url: url, method: .post, query: "{ test }", variables: nil, auth: .bearer(token: "my-token"), headers: [])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
