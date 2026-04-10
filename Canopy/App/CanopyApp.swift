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
        .modelContainer(for: [QueryTab.self, AppEnvironment.self, ActiveEnvironmentState.self])
        .defaultSize(width: 1200, height: 800)
    }
}
