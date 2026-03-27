import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar()
        } detail: {
            if let tab = appState.selectedQueryTab {
                QueryClientView(tab: tab)
            } else {
                VStack(spacing: 12) {
                    Text("Canopy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("A native GraphQL client for macOS")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Press \(Image(systemName: "command")) T to create a new query tab")
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
    }
}
