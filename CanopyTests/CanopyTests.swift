import Testing
@testable import Canopy

@Suite("App State Tests")
struct AppStateTests {
    @Test("Adding a tab creates a new tab and selects it")
    func addTab() {
        let state = AppState()
        #expect(state.tabs.isEmpty)

        state.addTab()

        #expect(state.tabs.count == 1)
        #expect(state.selectedTab == state.tabs.first?.id)
    }

    @Test("selectedQueryTab returns the correct tab")
    func selectedQueryTab() {
        let state = AppState()
        #expect(state.selectedQueryTab == nil)

        state.addTab()
        let tab = state.selectedQueryTab
        #expect(tab != nil)
        #expect(tab?.id == state.selectedTab)
    }

    @Test("Adding multiple tabs selects the latest")
    func addMultipleTabs() {
        let state = AppState()
        state.addTab()
        state.addTab()

        #expect(state.tabs.count == 2)
        #expect(state.selectedTab == state.tabs.last?.id)
    }
}
