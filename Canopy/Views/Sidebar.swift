import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedTab) {
            Section("Queries") {
                if appState.tabs.isEmpty {
                    Text("No queries yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.tabs) { tab in
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
