import SwiftUI

struct BottomPanel: View {
    @Bindable var tab: QueryTab
    @State private var selectedPanel = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedPanel) {
                Text("Variables").tag(0)
                Text("Headers").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selectedPanel {
            case 0:
                VariablesEditor(tab: tab)
            default:
                HeadersEditor(tab: tab)
            }
        }
    }
}
