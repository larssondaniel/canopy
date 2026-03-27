import SwiftUI

struct RequestPane: View {
    @Bindable var tab: QueryTab
    var onRun: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EndpointBar(tab: tab, onRun: onRun, onCancel: onCancel)
            Divider()
            VSplitView {
                QueryEditorView(tab: tab)
                    .frame(minHeight: 100)
                BottomPanel(tab: tab)
                    .frame(minHeight: 80)
            }
        }
    }
}
