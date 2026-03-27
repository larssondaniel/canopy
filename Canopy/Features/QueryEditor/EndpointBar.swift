import SwiftUI

struct EndpointBar: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var onRun: () -> Void
    var onCancel: () -> Void

    private var hasUnresolved: Bool {
        guard let env = activeEnvironment else { return false }
        let vars = env.variables

        if TemplateEngine.hasUnresolvedVariables(in: tab.endpoint, variables: vars) { return true }
        if TemplateEngine.hasUnresolvedVariables(in: tab.variables, variables: vars) { return true }

        for header in tab.headers {
            if TemplateEngine.hasUnresolvedVariables(in: header.value, variables: vars) { return true }
        }

        let auth = tab.authConfig.toAuthConfiguration()
        switch auth {
        case .bearer(let token):
            if TemplateEngine.hasUnresolvedVariables(in: token, variables: vars) { return true }
        case .apiKey(_, let value):
            if TemplateEngine.hasUnresolvedVariables(in: value, variables: vars) { return true }
        case .basic(let username, let password):
            if TemplateEngine.hasUnresolvedVariables(in: username, variables: vars) { return true }
            if TemplateEngine.hasUnresolvedVariables(in: password, variables: vars) { return true }
        case .none:
            break
        }

        return false
    }

    private var unresolvedVariableNames: [String] {
        guard let env = activeEnvironment else { return [] }
        let vars = env.variables
        var names: [String] = []

        let fields = [tab.endpoint, tab.variables] + tab.headers.map(\.value)
        for field in fields {
            for v in TemplateEngine.findVariables(in: field) where vars[v.name] == nil {
                if !names.contains(v.name) {
                    names.append(v.name)
                }
            }
        }
        return names
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $tab.method) {
                ForEach(HTTPMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .frame(width: 80)

            TemplateTextField(
                text: $tab.endpoint,
                placeholder: "https://example.com/graphql",
                activeEnvironment: activeEnvironment
            )

            if tab.isLoading {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button("Run") {
                    onRun()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(hasUnresolved)
                .help(hasUnresolved ? "Undefined variables: \(unresolvedVariableNames.map { "{{\($0)}}" }.joined(separator: ", "))" : "Send request (Cmd+Return)")
            }
        }
        .padding(8)
    }
}
