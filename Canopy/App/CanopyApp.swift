import SwiftUI
import SwiftData

@main
struct CanopyApp: App {
    @State private var appState = AppState()
    @State private var schemaStore = SchemaStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(schemaStore)
        }
        .modelContainer(for: [QueryTab.self, Project.self, ProjectEnvironment.self])
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
    }
}
