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
}
