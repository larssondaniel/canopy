import SwiftUI
import SwiftData

struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryTab.sortOrder) private var tabs: [QueryTab]

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedTab) {
            Section("Queries") {
                if tabs.isEmpty {
                    Text("No queries yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tabs) { tab in
                        Label(tab.name, systemImage: "arrow.right.circle")
                            .tag(tab.id)
                    }
                }
            }

            Section("Collections") {
                Text("No collections yet")
                    .foregroundStyle(.secondary)
            }

            Section("Environments") {
                Text("No environments yet")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Canopy")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.addTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                }
            }
        }
    }
}
