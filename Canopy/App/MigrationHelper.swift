import Foundation
import SwiftData

@MainActor
enum MigrationHelper {
    /// Assigns orphaned QueryTabs (those with `project == nil`) to the first existing project.
    /// This preserves user data when upgrading from the single-project era.
    static func adoptOrphanedTabs(context: ModelContext) {
        let orphanDescriptor = FetchDescriptor<QueryTab>(
            predicate: #Predicate<QueryTab> { $0.project == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        guard let orphans = try? context.fetch(orphanDescriptor), !orphans.isEmpty else { return }

        let projectDescriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.createdAt)])
        guard let project = try? context.fetch(projectDescriptor).first else { return }

        for tab in orphans {
            tab.project = project
        }
    }

    /// Returns an existing QueryTab for the given project, or creates one if none exist.
    static func ensureQueryTab(for project: Project, context: ModelContext) -> QueryTab {
        if let existing = project.queryTabs.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
            return existing
        }
        let tab = QueryTab()
        tab.project = project
        context.insert(tab)
        return tab
    }
}
