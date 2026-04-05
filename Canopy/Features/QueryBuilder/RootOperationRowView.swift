import SwiftUI

/// Represents the three GraphQL operation types for the segmented filter.
enum OperationSegment: String, CaseIterable, Identifiable {
    case queries = "Queries"
    case mutations = "Mutations"
    case subscriptions = "Subscriptions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .queries: "magnifyingglass"
        case .mutations: "arrow.triangle.2.circlepath"
        case .subscriptions: "antenna.radiowaves.left.and.right"
        }
    }

    var accentColor: Color {
        switch self {
        case .queries: .blue
        case .mutations: .green
        case .subscriptions: .orange
        }
    }
}

/// A root-level operation row in the explorer. Click-to-toggle (no checkbox).
/// The entire row is clickable — selects/deselects the operation and expands/collapses children.
struct RootOperationRowView: View {
    let fieldName: String
    let typeName: String
    let operationType: OperationSegment
    let isSelected: Bool
    let isDeprecated: Bool
    var showTypes: Bool = false
    /// Full field data for the Inspect popover.
    var inspectableField: GraphQLField? = nil

    @SwiftUI.Environment(\.inspectFieldAction) private var inspectAction

    var body: some View {
        HStack(spacing: 4) {
            Text(fieldName)
                .fontWeight(.medium)
                .foregroundStyle(isDeprecated ? .secondary : .primary)
                .strikethrough(isDeprecated)

            Spacer()

            if showTypes {
                Text(typeName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .contentShape(Rectangle())
        .accessibilityLabel("\(fieldName)\(isSelected ? ", selected" : "")")
        .accessibilityHint("Click to \(isSelected ? "deselect" : "select")")
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
        }
    }
}
