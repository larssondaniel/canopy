import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var astService: QueryASTService
    @State private var requestFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                RequestPane(tab: tab, activeEnvironment: activeEnvironment)
                    .frame(width: max(200, geo.size.width * requestFraction))

                SplitDivider(fraction: $requestFraction, totalWidth: geo.size.width)

                ResponsePane(tab: tab)
                    .frame(minWidth: 200, maxWidth: .infinity)
            }
        }
    }
}

private struct SplitDivider: View {
    @Binding var fraction: CGFloat
    var totalWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .frame(width: 7)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newFraction = value.location.x / totalWidth
                        fraction = min(max(newFraction, 0.2), 0.8)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
