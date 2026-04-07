import SwiftUI

/// Identifies a row in the sidebar outline for focus tracking.
enum OutlineRowID: Hashable {
    case section(OperationSegment)
    case operation(OperationSegment, String) // segment + field name
    case field(String) // full path key like "user/id"
}

/// Manages keyboard navigation for the sidebar outline.
///
/// Provides a view modifier that intercepts key events on the sidebar List
/// and translates them into outline navigation: arrow keys move focus through
/// a flat sequence of visible rows, left/right collapse/expand, space toggles,
/// and typing redirects to the search field.
struct OutlineKeyboardModifier: ViewModifier {
    @Binding var focusedRow: OutlineRowID?
    @Binding var expandedPaths: Set<String>
    @Binding var expandedSections: Set<OperationSegment>
    @Binding var searchText: String
    let visibleRows: [OutlineRowID]
    let toggleRow: (OutlineRowID) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                handleKeyPress(press)
            }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Cmd+F: focus search
        if press.key == .init("f") && press.modifiers.contains(.command) {
            searchText = searchText // trigger focus (handled by .searchable)
            return .handled
        }

        // Escape: clear search
        if press.key == .escape {
            if !searchText.isEmpty {
                searchText = ""
                return .handled
            }
            return .ignored
        }

        switch press.key {
        case .upArrow:
            moveFocus(by: -1)
            return .handled
        case .downArrow:
            moveFocus(by: 1)
            return .handled
        case .leftArrow:
            return handleLeft()
        case .rightArrow:
            return handleRight()
        case .space:
            if let row = focusedRow {
                toggleRow(row)
                return .handled
            }
            return .ignored
        default:
            // Printable character: redirect to search
            if let char = press.characters.first, char.isLetter || char.isNumber {
                searchText = String(char)
                return .handled
            }
            return .ignored
        }
    }

    private func moveFocus(by offset: Int) {
        guard !visibleRows.isEmpty else { return }
        guard let current = focusedRow,
              let currentIndex = visibleRows.firstIndex(of: current) else {
            // No focus yet — focus first or last depending on direction
            focusedRow = offset > 0 ? visibleRows.first : visibleRows.last
            return
        }
        let newIndex = currentIndex + offset
        guard visibleRows.indices.contains(newIndex) else { return }
        focusedRow = visibleRows[newIndex]
    }

    private func handleLeft() -> KeyPress.Result {
        guard let row = focusedRow else { return .ignored }
        switch row {
        case .section(let segment):
            if expandedSections.contains(segment) {
                expandedSections.remove(segment)
                return .handled
            }
            return .ignored
        case .operation(let segment, let fieldName):
            if expandedPaths.contains(fieldName) {
                expandedPaths.remove(fieldName)
                return .handled
            }
            // Already collapsed — jump to parent section
            focusedRow = .section(segment)
            return .handled
        case .field(let pathKey):
            if expandedPaths.contains(pathKey) {
                expandedPaths.remove(pathKey)
                return .handled
            }
            // Jump to parent: remove last path component
            let components = pathKey.split(separator: "/")
            if components.count >= 2 {
                let parentKey = components.dropLast().joined(separator: "/")
                if components.count == 2 {
                    // Parent is a root operation — find its segment
                    if let parentRow = visibleRows.first(where: {
                        if case .operation(_, let name) = $0 { return name == parentKey }
                        return false
                    }) {
                        focusedRow = parentRow
                        return .handled
                    }
                }
                focusedRow = .field(parentKey)
                return .handled
            }
            return .ignored
        }
    }

    private func handleRight() -> KeyPress.Result {
        guard let row = focusedRow else { return .ignored }
        switch row {
        case .section(let segment):
            if !expandedSections.contains(segment) {
                expandedSections.insert(segment)
                return .handled
            }
            return .ignored
        case .operation(_, let fieldName):
            if !expandedPaths.contains(fieldName) {
                expandedPaths.insert(fieldName)
                return .handled
            }
            return .ignored
        case .field(let pathKey):
            if !expandedPaths.contains(pathKey) {
                expandedPaths.insert(pathKey)
                return .handled
            }
            return .ignored
        }
    }
}

extension View {
    func outlineKeyboardNavigation(
        focusedRow: Binding<OutlineRowID?>,
        expandedPaths: Binding<Set<String>>,
        expandedSections: Binding<Set<OperationSegment>>,
        searchText: Binding<String>,
        visibleRows: [OutlineRowID],
        toggleRow: @escaping (OutlineRowID) -> Void
    ) -> some View {
        modifier(OutlineKeyboardModifier(
            focusedRow: focusedRow,
            expandedPaths: expandedPaths,
            expandedSections: expandedSections,
            searchText: searchText,
            visibleRows: visibleRows,
            toggleRow: toggleRow
        ))
    }
}
