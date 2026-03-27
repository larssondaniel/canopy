import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryTab.sortOrder) private var tabs: [QueryTab]

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar()
        } detail: {
            if let selectedTab = appState.selectedTab,
               let tab = tabs.first(where: { $0.id == selectedTab }) {
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
        .onAppear {
            appState.modelContext = modelContext
        }
    }
}
