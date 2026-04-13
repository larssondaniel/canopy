import SwiftUI

struct RunCancelButton: View {
    var tab: QueryTab?
    var resolvedVariables: [String: String]
    var onRun: () -> Void
    var onCancel: () -> Void

    private var isLoading: Bool {
        tab?.isLoading ?? false
    }

    private var hasUnresolved: Bool {
        tab?.hasUnresolvedVariables(variables: resolvedVariables) ?? false
    }

    private var tooltip: String {
        if let names = tab?.unresolvedVariableNames(variables: resolvedVariables), !names.isEmpty {
            return "Undefined variables: \(names.map { "{{\($0)}}" }.joined(separator: ", "))"
        }
        return "Send request (\u{2318}\u{23CE})"
    }

    var body: some View {
        if isLoading {
            Button { onCancel() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .clipShape(Circle())
            .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button { onRun() } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(hasUnresolved)
            .help(tooltip)
        }
    }
}
