import SwiftUI

struct RequestPane: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?

    var body: some View {
        VSplitView {
            QueryEditorView(tab: tab)
                .frame(minHeight: 100)
            BottomPanel(tab: tab, activeEnvironment: activeEnvironment)
                .frame(minHeight: 80)
        }
    }
}
