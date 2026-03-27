import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            VStack {
                Text("Canopy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("A native GraphQL client for macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
    }
}

#Preview {
    ContentView()
}
