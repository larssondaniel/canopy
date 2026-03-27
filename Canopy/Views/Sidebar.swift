import SwiftUI

struct Sidebar: View {
    var body: some View {
        List {
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
                Button(action: {}) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}

#Preview {
    Sidebar()
}
