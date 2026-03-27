import SwiftUI
import SwiftData

struct Sidebar: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \QueryTab.sortOrder) private var tabs: [QueryTab]
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]

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
                if environments.isEmpty {
                    Text("No environments yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(environments) { env in
                        Label(env.name.isEmpty ? "Untitled" : env.name, systemImage: "globe")
                    }
                }
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
