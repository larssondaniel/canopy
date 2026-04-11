import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var astService: QueryASTService

    var body: some View {
        HSplitView {
            RequestPane(tab: tab, activeEnvironment: activeEnvironment, onRun: { run() }, onCancel: cancel)
                .frame(minWidth: 300)
            ResponsePane(tab: tab)
                .frame(minWidth: 300)
        }
    }

    @SwiftUI.Environment(\.runOperationAction) private var runOperationAction

    private func run() {
        runOperationAction?.run(.queries)
    }

    private func cancel() {
        tab.currentTask?.cancel()
        tab.isLoading = false
    }
}
