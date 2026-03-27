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
}
