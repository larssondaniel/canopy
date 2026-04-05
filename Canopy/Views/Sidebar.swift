import SwiftUI

struct Sidebar: View {
    var activeTab: QueryTab?
    var astService: QueryASTService

    var body: some View {
        QueryExplorerView(
            activeTab: activeTab,
            astService: astService
        )
        .navigationTitle("Explorer")
    }
}
