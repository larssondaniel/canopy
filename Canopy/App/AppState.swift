import SwiftUI
import Observation

@Observable
final class AppState {
    var selectedTab: UUID?
    var tabs: [QueryTab] = []

    func addTab() {
        let tab = QueryTab()
        tabs.append(tab)
        selectedTab = tab.id
    }
}

struct QueryTab: Identifiable {
    let id = UUID()
    var name: String = "Untitled"
    var endpoint: String = ""
    var query: String = ""
    var variables: String = ""
    var response: String?
}
