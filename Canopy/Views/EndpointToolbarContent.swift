import SwiftUI

struct EndpointToolbarContent: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var hasUnresolved: Bool
    var runButtonTooltip: String
    var onRun: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            runCancelButton
            methodMenu
            urlField
            shortcutHint
        }
        .tint(nil)
    }

    // MARK: - Run / Cancel

    @ViewBuilder
    private var runCancelButton: some View {
        if tab.isLoading {
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
            .tint(.blue)
            .clipShape(Circle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(hasUnresolved)
            .help(runButtonTooltip)
        }
    }

    // MARK: - HTTP Method

    @ViewBuilder
    private var methodMenu: some View {
        let menu = Menu {
            ForEach(HTTPMethod.allCases, id: \.self) { method in
                Button(method.rawValue) { tab.method = method }
            }
        } label: {
            Text(tab.method.rawValue)
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()

        if #available(macOS 26.0, *) {
            menu.glassEffect(.identity)
        } else {
            menu
        }
    }

    // MARK: - URL Field

    @ViewBuilder
    private var urlField: some View {
        let field = TemplateTextField(
            text: $tab.endpoint,
            placeholder: "https://example.com/graphql",
            activeEnvironment: activeEnvironment
        )
        .font(.system(size: 12, design: .monospaced))
        .frame(minWidth: 300, maxWidth: 600)

        if #available(macOS 26.0, *) {
            field.glassEffect(.identity)
        } else {
            field
        }
    }

    // MARK: - Shortcut Hint

    private var shortcutHint: some View {
        Text("⌘⏎")
            .foregroundStyle(.tertiary)
            .font(.system(size: 11))
    }
}
