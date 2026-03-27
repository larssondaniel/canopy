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

            CommandGroup(after: .newItem) {
                Button("Close Tab") {
                    if let tab = appState.selectedTab {
                        appState.closeTab(tab)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Show Next Tab") {
                    appState.cycleTab(forward: true)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Show Previous Tab") {
                    appState.cycleTab(forward: false)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
    }
}
