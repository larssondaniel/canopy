import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class AppState {
    var modelContext: ModelContext?
    var showEnvironments = false

    /// Returns the single query tab, creating one if needed.
    func ensureQueryTab() -> QueryTab? {
        guard let modelContext else { return nil }
        let tabs = (try? modelContext.fetch(FetchDescriptor<QueryTab>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        if let first = tabs.first {
            return first
        }
        let tab = QueryTab()
        modelContext.insert(tab)
        return tab
    }
}
