import Testing
import SwiftData
import Foundation
@testable import Canopy

@Suite("MigrationHelper Tests")
struct MigrationHelperTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: QueryTab.self, Project.self, ProjectEnvironment.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test("adoptOrphanedTabs assigns orphaned tabs to first project")
    @MainActor func adoptOrphanedTabs() throws {
        let context = try makeContext()

        let project = Project(name: "My Project", endpointPattern: "{{host}}")
        context.insert(project)

        let tab1 = QueryTab()
        tab1.name = "Tab 1"
        context.insert(tab1)

        let tab2 = QueryTab()
        tab2.name = "Tab 2"
        context.insert(tab2)

        try context.save()

        // Tabs start with no project
        #expect(tab1.project == nil)
        #expect(tab2.project == nil)

        MigrationHelper.adoptOrphanedTabs(context: context)

        #expect(tab1.project === project)
        #expect(tab2.project === project)
        #expect(project.queryTabs.count == 2)
    }

    @Test("adoptOrphanedTabs does nothing when no orphans exist")
    @MainActor func noOrphansNoOp() throws {
        let context = try makeContext()

        let project = Project(name: "My Project")
        context.insert(project)

        let tab = QueryTab()
        tab.project = project
        context.insert(tab)

        try context.save()

        MigrationHelper.adoptOrphanedTabs(context: context)

        #expect(tab.project === project)
        #expect(project.queryTabs.count == 1)
    }

    @Test("adoptOrphanedTabs does nothing when no projects exist")
    @MainActor func noProjectsNoOp() throws {
        let context = try makeContext()

        let tab = QueryTab()
        context.insert(tab)
        try context.save()

        MigrationHelper.adoptOrphanedTabs(context: context)

        #expect(tab.project == nil)
    }

    @Test("ensureQueryTab returns existing tab for project")
    @MainActor func ensureReturnsExisting() throws {
        let context = try makeContext()

        let project = Project(name: "Test")
        context.insert(project)

        let existingTab = QueryTab()
        existingTab.project = project
        existingTab.name = "Existing"
        context.insert(existingTab)

        try context.save()

        let result = MigrationHelper.ensureQueryTab(for: project, context: context)
        #expect(result.name == "Existing")
        #expect(result === existingTab)
    }

    @Test("ensureQueryTab creates new tab when project has none")
    @MainActor func ensureCreatesNew() throws {
        let context = try makeContext()

        let project = Project(name: "Test")
        context.insert(project)
        try context.save()

        let result = MigrationHelper.ensureQueryTab(for: project, context: context)
        #expect(result.project === project)
        #expect(result.name == "Untitled")
    }
}

@Suite("QueryTab-Project Relationship Tests")
struct QueryTabProjectRelationshipTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: QueryTab.self, Project.self, ProjectEnvironment.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test("QueryTab starts with nil project")
    func nilProjectByDefault() {
        let tab = QueryTab()
        #expect(tab.project == nil)
    }

    @Test("Can assign project to tab")
    @MainActor func assignProject() throws {
        let context = try makeContext()

        let project = Project(name: "Test")
        context.insert(project)

        let tab = QueryTab()
        tab.project = project
        context.insert(tab)

        try context.save()

        #expect(tab.project === project)
        #expect(project.queryTabs.contains(where: { $0.id == tab.id }))
    }

    @Test("Project starts with empty queryTabs")
    func emptyQueryTabsByDefault() {
        let project = Project(name: "Test")
        #expect(project.queryTabs.isEmpty)
    }
}
