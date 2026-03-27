import SwiftUI

struct EndpointBar: View {
    @Bindable var tab: QueryTab
    var onRun: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $tab.method) {
                ForEach(HTTPMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .frame(width: 80)

            TextField("https://example.com/graphql", text: $tab.endpoint)
                .textFieldStyle(.roundedBorder)

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
            }
        }
        .padding(8)
    }
}
