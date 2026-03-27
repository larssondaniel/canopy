import SwiftUI
import SwiftData

struct TabBarView: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @Query(sort: \QueryTab.sortOrder) private var queryTabs: [QueryTab]

    @State private var draggedTab: ContentTab?

    private func queryTab(for contentTab: ContentTab) -> QueryTab? {
        guard let id = contentTab.queryID else { return nil }
        return queryTabs.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(appState.openTabs) { tab in
                        TabBarItemView(
                            tab: tab,
                            isSelected: appState.selectedTab == tab,
                            queryTab: queryTab(for: tab),
                            onSelect: { appState.selectTab(tab) },
                            onClose: { appState.closeTab(tab) },
                            onCloseOthers: { appState.closeOtherTabs(tab) }
                        )
                        .draggable(tab.id) {
                            // Drag preview
                            Text(queryTab(for: tab)?.name ?? "Tab")
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(.ultraThinMaterial))
                        }
                        .dropDestination(for: String.self) { _, _ in
                            guard let dragged = draggedTab,
                                  let fromIndex = appState.openTabs.firstIndex(of: dragged),
                                  let toIndex = appState.openTabs.firstIndex(of: tab),
                                  fromIndex != toIndex else { return false }
                            appState.moveTab(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                            return true
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()
                .frame(height: 16)

            Button {
                appState.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help("New Tab")
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
