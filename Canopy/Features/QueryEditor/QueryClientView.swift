import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var astService: QueryASTService

    var body: some View {
        HSplitView {
            RequestPane(tab: tab, activeEnvironment: activeEnvironment)
                .frame(minWidth: 200)
            ResponsePane(tab: tab)
                .frame(minWidth: 200)
        }
    }
}
