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
        }
    }

    @ViewBuilder
    private var runCancelButton: some View {
        if tab.isLoading {
            Button { onCancel() } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button { onRun() } label: {
                Label("Run", systemImage: "play.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(hasUnresolved)
            .help(runButtonTooltip)
        }
    }

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

    @ViewBuilder
    private var urlField: some View {
        let field = TemplateTextField(
            text: $tab.endpoint,
            placeholder: "https://example.com/graphql",
            activeEnvironment: activeEnvironment
        )
        .font(.system(size: 12, design: .monospaced))
        .frame(minWidth: 200, maxWidth: .infinity)

        if #available(macOS 26.0, *) {
            field.glassEffect(.identity)
        } else {
            field
        }
    }
}
