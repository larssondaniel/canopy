import SwiftUI

struct RunCancelButton: View {
    var isLoading: Bool
    var hasUnresolved: Bool
    var runButtonTooltip: String
    var onRun: () -> Void
    var onCancel: () -> Void

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
            .help(runButtonTooltip)
        }
    }
}

struct EndpointToolbarContent: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?

    var body: some View {
        HStack(spacing: 8) {
            methodMenu
            urlField
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
