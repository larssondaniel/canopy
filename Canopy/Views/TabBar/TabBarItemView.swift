import SwiftUI
import SwiftData

struct TabBarItemView: View {
    let tab: ContentTab
    let isSelected: Bool
    let queryTab: QueryTab?
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void

    @State private var isHovering = false
    @State private var isEditingName = false
    @State private var editName = ""

    private var displayName: String {
        switch tab {
        case .query:
            queryTab?.name ?? "Untitled"
        case .environments:
            "Environments"
        }
    }

    private var icon: String {
        switch tab {
        case .query: "arrow.right.circle"
        case .environments: "square.stack.3d.up.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .primary : .secondary)

            if isEditingName, let queryTab {
                TextField("Name", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 80)
                    .onSubmit {
                        queryTab.name = editName
                        isEditingName = false
                    }
                    .onExitCommand {
                        isEditingName = false
                    }
            } else {
                Text(displayName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }

            if isHovering || isSelected {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            if case .query = tab {
                editName = displayName
                isEditingName = true
            }
        }
        .contextMenu {
            Button("Close Tab") { onClose() }
            Button("Close Other Tabs") { onCloseOthers() }
        }
    }
}
