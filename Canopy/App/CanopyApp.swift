import SwiftUI
import SwiftData

@main
struct CanopyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(for: [QueryTab.self, AppEnvironment.self, ActiveEnvironmentState.self])
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appState.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
