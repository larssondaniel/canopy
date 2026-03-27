import SwiftUI

struct QueryEditorView: View {
    @Bindable var tab: QueryTab

    var body: some View {
        TextEditor(text: $tab.query)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.visible)
    }
}
