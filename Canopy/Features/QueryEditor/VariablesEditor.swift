import SwiftUI

struct VariablesEditor: View {
    @Bindable var tab: QueryTab

    var body: some View {
        TextEditor(text: $tab.variables)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.visible)
    }
}
