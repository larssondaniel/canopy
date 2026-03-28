import SwiftUI

struct VariablesEditor: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?

    var body: some View {
        TemplateTextEditor(
            text: $tab.variables,
            activeEnvironment: activeEnvironment
        )
    }
}
