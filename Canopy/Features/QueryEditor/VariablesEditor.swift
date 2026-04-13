import SwiftUI

struct VariablesEditor: View {
    @Bindable var tab: QueryTab
    var resolvedVariables: [String: String]

    var body: some View {
        TemplateTextEditor(
            text: $tab.variables,
            environmentVariables: resolvedVariables
        )
    }
}
