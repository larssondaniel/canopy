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

    var selectedQueryTab: QueryTab? {
        guard let selectedTab else { return nil }
        return tabs.first { $0.id == selectedTab }
    }
}
