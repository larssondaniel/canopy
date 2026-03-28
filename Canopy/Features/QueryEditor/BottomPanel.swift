import SwiftUI

struct BottomPanel: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    @State private var selectedPanel = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedPanel) {
                Text("Variables").tag(0)
                Text("Headers").tag(1)
                Text("Auth").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selectedPanel {
            case 0:
                VariablesEditor(tab: tab, activeEnvironment: activeEnvironment)
            case 1:
                HeadersEditor(tab: tab, activeEnvironment: activeEnvironment)
            default:
                AuthEditor(tab: tab, activeEnvironment: activeEnvironment)
            }
        }
    }
}
