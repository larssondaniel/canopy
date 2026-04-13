import SwiftUI
import SwiftData

@main
struct CanopyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appState = AppState()
    @State private var schemaStore = SchemaStore()

    var body: some Scene {
        Window("Welcome to Canopy", id: "welcome") {
            WelcomeView()
                .environment(appState)
        }
        .modelContainer(for: [QueryTab.self, Project.self, ProjectEnvironment.self])
        .defaultSize(width: 800, height: 500)

        WindowGroup(for: UUID.self) { $projectId in
            ProjectWindow(projectId: projectId)
                .environment(appState)
                .environment(schemaStore)
        }
        .modelContainer(for: [QueryTab.self, Project.self, ProjectEnvironment.self])
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)

        .commands {
            CommandGroup(after: .newItem) {
                Button("New Project...") {
                    appDelegate.showNewProjectSheet()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
