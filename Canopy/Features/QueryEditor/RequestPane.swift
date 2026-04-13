import SwiftUI

struct RequestPane: View {
    @Bindable var tab: QueryTab
    var resolvedVariables: [String: String]

    var body: some View {
        VSplitView {
            QueryEditorView(tab: tab)
                .frame(minHeight: 100)
            BottomPanel(tab: tab, resolvedVariables: resolvedVariables)
                .frame(minHeight: 80)
        }
    }
}
