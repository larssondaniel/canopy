import SwiftUI

/// Shows the contents of a single GraphQL type: fields, enum values, interfaces, etc.
struct TypeDetailView: View {
    let type: GraphQLFullType
    @Binding var selectedTypeName: String?

    var body: some View {
        Group {
            if let description = type.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            // Interfaces
            if let interfaces = type.interfaces, !interfaces.isEmpty {
                HStack(spacing: 4) {
                    Text("implements")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ForEach(interfaces, id: \.self) { iface in
                        TypeRefView(typeRef: iface.toTypeRef()) { name in
                            selectedTypeName = name
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 4)
            }

            // Fields (OBJECT, INTERFACE)
            if let fields = type.fields {
                ForEach(fields) { field in
                    FieldRowView(field: field, selectedTypeName: $selectedTypeName)
                }
            }

            // Input fields (INPUT_OBJECT)
            if let inputFields = type.inputFields {
                ForEach(inputFields) { inputField in
                    InputValueRow(inputValue: inputField, selectedTypeName: $selectedTypeName)
                }
            }

            // Enum values
            if let enumValues = type.enumValues {
                ForEach(enumValues) { value in
                    EnumValueRow(value: value)
                }
            }

            // Union possible types
            if let possibleTypes = type.possibleTypes, !possibleTypes.isEmpty {
                ForEach(possibleTypes, id: \.self) { typeRef in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                        TypeRefView(typeRef: typeRef.toTypeRef()) { name in
                            selectedTypeName = name
                        }
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }
}

// MARK: - Field Row

private struct FieldRowView: View {
    let field: GraphQLField
    @Binding var selectedTypeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(field.name)
                    .fontWeight(.medium)
                    .strikethrough(field.isDeprecated)
                    .foregroundStyle(field.isDeprecated ? .secondary : .primary)

                if !field.args.isEmpty {
                    Text("(\(field.args.map { "\($0.name):" }.joined(separator: " ")))")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }

                Text(":")
                    .foregroundStyle(.secondary)

                TypeRefView(typeRef: field.type.toTypeRef()) { name in
                    selectedTypeName = name
                }
            }
            .font(.system(.caption, design: .monospaced))

            if let description = field.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if field.isDeprecated, let reason = field.deprecationReason {
                Text("Deprecated: \(reason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.leading, 8)
    }
}

// MARK: - Input Value Row

private struct InputValueRow: View {
    let inputValue: GraphQLInputValue
    @Binding var selectedTypeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(inputValue.name)
                    .fontWeight(.medium)
                Text(":")
                    .foregroundStyle(.secondary)
                TypeRefView(typeRef: inputValue.type.toTypeRef()) { name in
                    selectedTypeName = name
                }
                if let defaultValue = inputValue.defaultValue {
                    Text("= \(defaultValue)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(.caption, design: .monospaced))

            if let description = inputValue.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 8)
    }
}

// MARK: - Enum Value Row

private struct EnumValueRow: View {
    let value: GraphQLEnumValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .strikethrough(value.isDeprecated)
                .foregroundStyle(value.isDeprecated ? .secondary : .primary)

            if let description = value.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if value.isDeprecated, let reason = value.deprecationReason {
                Text("Deprecated: \(reason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.leading, 8)
    }
}
