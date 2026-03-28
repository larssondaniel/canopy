import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class AppState {
    var openTabs: [ContentTab] = []
    var selectedTab: ContentTab?
    var modelContext: ModelContext?

    /// MRU stack — most recently used tab is at the front
    private var recentTabOrder: [ContentTab] = []

    // MARK: - Tab Management

    func addTab() {
        guard let modelContext else { return }
        let tabs = (try? modelContext.fetch(FetchDescriptor<QueryTab>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let tab = QueryTab()
        tab.sortOrder = (tabs.last?.sortOrder ?? -1) + 1
        modelContext.insert(tab)
        let contentTab = ContentTab.query(tab.id)
        openTabs.append(contentTab)
        selectTab(contentTab)
    }

    func closeTab(_ tab: ContentTab) {
        guard let modelContext else { return }
        guard let index = openTabs.firstIndex(of: tab) else { return }

        // Cancel in-flight tasks for query tabs
        if let queryID = tab.queryID,
           let queryTab = fetchQueryTab(queryID) {
            queryTab.currentTask?.cancel()
            modelContext.delete(queryTab)
        }

        openTabs.remove(at: index)
        recentTabOrder.removeAll { $0 == tab }

        // Select next tab via MRU, or auto-create if last tab closed
        if selectedTab == tab {
            if let mruTab = recentTabOrder.first(where: { openTabs.contains($0) }) {
                selectTab(mruTab)
            } else if let firstTab = openTabs.first {
                selectTab(firstTab)
            } else {
                // Last tab closed — auto-create a new one
                addTab()
            }
        }
    }

    func selectTab(_ tab: ContentTab) {
        selectedTab = tab
        // Push to front of MRU stack
        recentTabOrder.removeAll { $0 == tab }
        recentTabOrder.insert(tab, at: 0)
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        openTabs.move(fromOffsets: source, toOffset: destination)
    }

    func openEnvironmentsTab() {
        if let existing = openTabs.first(where: { $0.isEnvironments }) {
            selectTab(existing)
        } else {
            let tab = ContentTab.environments
            openTabs.append(tab)
            selectTab(tab)
        }
    }

    func closeOtherTabs(_ tab: ContentTab) {
        guard let modelContext else { return }
        let tabsToClose = openTabs.filter { $0 != tab }
        for t in tabsToClose {
            if let queryID = t.queryID, let queryTab = fetchQueryTab(queryID) {
                queryTab.currentTask?.cancel()
                modelContext.delete(queryTab)
            }
        }
        openTabs = [tab]
        recentTabOrder = [tab]
        selectTab(tab)
    }

    func cycleTab(forward: Bool) {
        guard openTabs.count > 1, let selectedTab else { return }
        guard let currentIndex = openTabs.firstIndex(of: selectedTab) else { return }
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % openTabs.count
        } else {
            nextIndex = (currentIndex - 1 + openTabs.count) % openTabs.count
        }
        selectTab(openTabs[nextIndex])
    }

    // MARK: - Initialization

    func initializeTabs(from queryTabs: [QueryTab]) {
        guard openTabs.isEmpty else { return }
        openTabs = queryTabs.map { .query($0.id) }
        if let first = openTabs.first {
            selectTab(first)
        }
    }

    // MARK: - Helpers

    private func fetchQueryTab(_ id: UUID) -> QueryTab? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<QueryTab>()
        descriptor.predicate = #Predicate { $0.id == id }
        return try? modelContext.fetch(descriptor).first
    }
}
