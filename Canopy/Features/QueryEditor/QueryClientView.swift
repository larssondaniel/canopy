import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    private let client = GraphQLClient()

    var body: some View {
        HSplitView {
            RequestPane(tab: tab, onRun: run, onCancel: cancel)
                .frame(minWidth: 300)
            ResponsePane(tab: tab)
                .frame(minWidth: 300)
        }
    }

    private func run() {
        tab.currentTask?.cancel()
        tab.currentTask = Task {
            await client.send(tab: tab)
        }
    }

    private func cancel() {
        tab.currentTask?.cancel()
        tab.isLoading = false
    }
}
