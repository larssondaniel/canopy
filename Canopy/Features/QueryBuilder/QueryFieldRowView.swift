import SwiftUI

/// A single field row in the Explorer tree.
/// Passes only value types for SwiftUI body-skip optimization.
/// Uses environment for toggle callback instead of closure parameter.
struct QueryFieldRowView: View {
    let fieldName: String
    let typeName: String
    let isSelected: Bool
    let isDeprecated: Bool
    let isCircular: Bool
    let hasArguments: Bool
    let isDisabled: Bool
    let parentPath: [String]
    var rootTypeName: String? = nil

    @SwiftUI.Environment(\.toggleFieldAction) private var toggleAction

    var body: some View {
        HStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in
                    toggleAction?.toggle(fieldName, parentPath, rootTypeName)
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(isDisabled)

            Text(fieldName)
                .fontWeight(.medium)
                .strikethrough(isDeprecated)
                .foregroundStyle(isDeprecated ? .secondary : .primary)

            if isCircular {
                Text("(circular)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(typeName)
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .monospaced))
        .accessibilityLabel("\(fieldName), \(typeName)")
        .contextMenu {
            Button("Copy Field Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fieldName, forType: .string)
            }
            Button("Copy Type Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(typeName, forType: .string)
            }
        }
    }
}
