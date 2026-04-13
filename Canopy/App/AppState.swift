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

    /// Returns the single project, creating a default one if needed.
    func ensureProject() -> Project? {
        guard let modelContext else { return nil }
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let first = projects.first {
            return first
        }
        let project = Project(
            name: "Untitled Project",
            endpointPattern: "{{host}}",
            defaultVariables: [Variable(key: "host")]
        )
        modelContext.insert(project)
        return project
    }
}
