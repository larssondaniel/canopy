import SwiftUI

struct RequestPane: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var onRun: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EndpointBar(tab: tab, activeEnvironment: activeEnvironment, onRun: onRun, onCancel: onCancel)
            Divider()
            VSplitView {
                QueryEditorView(tab: tab)
                    .frame(minHeight: 100)
                BottomPanel(tab: tab, activeEnvironment: activeEnvironment)
                    .frame(minHeight: 80)
            }
        }
    }
}
