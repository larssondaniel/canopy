import SwiftUI

@main
struct CanopyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    // TODO: Add new query tab
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
