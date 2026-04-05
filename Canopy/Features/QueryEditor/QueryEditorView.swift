import SwiftUI

struct QueryEditorView: View {
    @Bindable var tab: QueryTab

    var body: some View {
        GraphQLTextEditor(text: $tab.query)
    }
}
