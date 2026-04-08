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
    var operationType: OperationSegment = .queries
    var showTypes: Bool = false
    var depth: Int = 0
    /// Full field data for the Inspect popover (optional — not all callers have it).
    var inspectableField: GraphQLField? = nil

    @SwiftUI.Environment(\.toggleFieldAction) private var toggleAction
    @SwiftUI.Environment(\.inspectFieldAction) private var inspectAction
    @SwiftUI.Environment(\.setFocusedRowAction) private var setFocusAction

    private var pathKey: String {
        (parentPath + [fieldName]).joined(separator: "/")
    }

    var body: some View {
        HStack(spacing: 4) {
            // Indent guide lines
            if depth > 0 {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 0.5)
                        .padding(.vertical, -2)
                }
                .frame(width: CGFloat(depth) * 12)
            }

            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in
                    setFocusAction?.setFocus(.field(pathKey))
                    toggleAction?.toggle(fieldName, parentPath, rootTypeName, operationType)
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(isDisabled)

            Text(fieldName)
                .fontWeight(isSelected ? .semibold : .regular)
                .strikethrough(isDeprecated)
                .foregroundStyle(isDeprecated ? .tertiary : .secondary)

            if isCircular {
                Text("(circular)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if showTypes {
                Text(typeName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .contentShape(Rectangle())
        .onTapGesture {
            setFocusAction?.setFocus(.field(pathKey))
        }
        .accessibilityLabel("\(fieldName)\(showTypes ? ", \(typeName)" : "")")
        .contextMenu {
            if let field = inspectableField {
                Button("Inspect") {
                    inspectAction?.inspect(field, typeName)
                }
                Divider()
            }
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
