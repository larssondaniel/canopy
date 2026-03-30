import SwiftUI

/// Renders a GraphQL type reference with clickable named types.
/// Recursive: [User!]! renders as "[" + TypeRefView(User!) + "]" + "!"
struct TypeRefView: View {
    let typeRef: GraphQLTypeRef
    let onNavigate: (String) -> Void

    var body: some View {
        switch typeRef {
        case .named(let name):
            Button(name) {
                onNavigate(name)
            }
            .buttonStyle(.link)
            .font(.system(.body, design: .monospaced))
        case .nonNull(let inner):
            HStack(spacing: 0) {
                TypeRefView(typeRef: inner, onNavigate: onNavigate)
                Text("!")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        case .list(let inner):
            HStack(spacing: 0) {
                Text("[")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
                TypeRefView(typeRef: inner, onNavigate: onNavigate)
                Text("]")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}
