import SwiftUI

struct Sidebar: View {
    var activeTab: QueryTab?
    var astService: QueryASTService

    @State private var selectedTab: SidebarTab = .explorer
    @State private var explorerSearchText = ""
    @State private var schemaSearchText = ""

    enum SidebarTab: String, CaseIterable {
        case explorer = "Explorer"
        case schema = "Schema"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            switch selectedTab {
            case .explorer:
                QueryExplorerView(
                    activeTab: activeTab,
                    astService: astService
                )
            case .schema:
                SchemaExplorerView()
            }
        }
        .navigationTitle(selectedTab == .explorer ? "Explorer" : "Schema")
    }
}
