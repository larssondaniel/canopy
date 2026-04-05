import SwiftUI

/// Info needed to display the inspect popover for a field.
struct InspectedFieldInfo: Identifiable {
    let id = UUID()
    let field: GraphQLField
    let resolvedTypeName: String
}

/// Popover showing field details: name, type, description, arguments, deprecation.
struct FieldInspectPopover: View {
    let field: GraphQLField
    let resolvedTypeName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Field name and type
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)

                Text(field.type.toTypeRef().displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            Divider()

            // Description
            if let description = field.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No description")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            // Deprecation
            if field.isDeprecated {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Deprecated")
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }

                if let reason = field.deprecationReason, !reason.isEmpty {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }

            // Arguments
            if !field.args.isEmpty {
                Divider()

                Text("Arguments")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(field.args) { arg in
                            ArgumentDetailRow(arg: arg)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 350)
    }
}

// MARK: - Argument Detail Row

private struct ArgumentDetailRow: View {
    let arg: GraphQLInputValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(arg.name)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)

                Text(":")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(arg.type.toTypeRef().displayString)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.blue)

                if let defaultValue = arg.defaultValue {
                    Text("= \(defaultValue)")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            if let description = arg.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.leading, 8)
    }
}
