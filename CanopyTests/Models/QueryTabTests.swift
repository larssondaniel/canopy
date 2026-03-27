import Testing
@testable import Canopy

@Suite("QueryTab Tests")
struct QueryTabTests {
    @Test("Default values are set correctly")
    func defaultValues() {
        let tab = QueryTab()
        #expect(tab.name == "Untitled")
        #expect(tab.endpoint == "")
        #expect(tab.query == "")
        #expect(tab.variables == "")
        #expect(tab.method == .post)
        #expect(tab.headers.isEmpty)
        #expect(tab.authConfiguration.authType == .none)
        #expect(tab.responseBody == nil)
        #expect(tab.responseStatusCode == nil)
        #expect(tab.responseTime == nil)
        #expect(tab.responseSize == nil)
        #expect(tab.responseHeaders == nil)
        #expect(tab.isLoading == false)
        #expect(tab.error == nil)
        #expect(tab.currentTask == nil)
    }

    @Test("Each tab has a unique ID")
    func uniqueIDs() {
        let tab1 = QueryTab()
        let tab2 = QueryTab()
        #expect(tab1.id != tab2.id)
    }

    @Test("Properties are mutable")
    func mutableProperties() {
        let tab = QueryTab()
        tab.name = "My Query"
        tab.endpoint = "https://api.example.com/graphql"
        tab.query = "{ users { id } }"
        tab.variables = """
        {"limit": 10}
        """
        tab.method = .get
        tab.isLoading = true

        #expect(tab.name == "My Query")
        #expect(tab.endpoint == "https://api.example.com/graphql")
        #expect(tab.query == "{ users { id } }")
        #expect(tab.method == .get)
        #expect(tab.isLoading == true)
    }
}
