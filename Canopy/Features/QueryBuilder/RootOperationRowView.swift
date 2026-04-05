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
    let hasPreservedSelections: Bool
    var showTypes: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(fieldName)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundStyle(isDeprecated ? .secondary : operationType.accentColor)
                .strikethrough(isDeprecated)

            if hasPreservedSelections && !isSelected {
                Circle()
                    .fill(operationType.accentColor.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .help("Has preserved selections")
            }

            Spacer()

            if showTypes {
                Text(typeName)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .contentShape(Rectangle())
        .accessibilityLabel("\(fieldName)\(isSelected ? ", selected" : "")")
        .accessibilityHint("Click to \(isSelected ? "deselect" : "select")")
    }
}
