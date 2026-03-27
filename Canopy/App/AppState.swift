import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class AppState {
    var selectedTab: UUID?
    var modelContext: ModelContext?

    func addTab() {
        guard let modelContext else { return }
        let tabs = (try? modelContext.fetch(FetchDescriptor<QueryTab>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let tab = QueryTab()
        tab.sortOrder = (tabs.last?.sortOrder ?? -1) + 1
        modelContext.insert(tab)
        selectedTab = tab.id
    }
}
