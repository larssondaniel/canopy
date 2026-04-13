import SwiftUI

// MARK: - Run / Cancel Button (isolated in its own ToolbarItem)

struct RunCancelButton: View {
    var tab: QueryTab?
    var activeEnvironment: AppEnvironment?
    var onRun: () -> Void
    var onCancel: () -> Void

    private var isLoading: Bool {
        tab?.isLoading ?? false
    }

    private var hasUnresolved: Bool {
        tab?.hasUnresolvedVariables(environment: activeEnvironment) ?? false
    }

    private var tooltip: String {
        if let names = tab?.unresolvedVariableNames(environment: activeEnvironment), !names.isEmpty {
            return "Undefined variables: \(names.map { "{{\($0)}}" }.joined(separator: ", "))"
        }
        return "Send request (⌘⏎)"
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

// MARK: - Method + URL (in .principal ToolbarItem)

struct EndpointToolbarContent: View {
    var tab: QueryTab?
    var activeEnvironment: AppEnvironment?
    @State private var isMethodHovering = false

    var body: some View {
        if let tab {
            @Bindable var tab = tab
            HStack(spacing: 8) {
                methodMenu(method: tab.method, setMethod: { tab.method = $0 })
                urlField(endpoint: $tab.endpoint)
                shortcutHint
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 300, idealWidth: 600, maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func methodMenu(method: HTTPMethod, setMethod: @escaping (HTTPMethod) -> Void) -> some View {
        let menu = Menu {
            ForEach(HTTPMethod.allCases, id: \.self) { m in
                Button(m.rawValue) { setMethod(m) }
            }
        } label: {
            HStack(spacing: 2) {
                Text(method.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isMethodHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: .capsule
            )
            .onHover { isMethodHovering = $0 }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()

        if #available(macOS 26.0, *) {
            menu.glassEffect(.identity)
        } else {
            menu
        }
    }

    @ViewBuilder
    private func urlField(endpoint: Binding<String>) -> some View {
        let field = TemplateURLField(
            url: endpoint,
            placeholder: "https://example.com/graphql",
            activeEnvironment: activeEnvironment
        )
        .frame(maxWidth: .infinity)

        if #available(macOS 26.0, *) {
            field.glassEffect(.identity)
        } else {
            field
        }
    }

    private var shortcutHint: some View {
        Text("⌘⏎")
            .foregroundStyle(.tertiary)
            .font(.system(size: 11))
    }
}
