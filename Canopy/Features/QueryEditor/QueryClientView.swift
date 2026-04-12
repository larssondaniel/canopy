import SwiftUI

struct QueryClientView: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
    var astService: QueryASTService
    @State private var dividerPosition: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let position = dividerPosition ?? geo.size.width * 0.5
            let minPos: CGFloat = 200
            let maxPos = max(geo.size.width - 200, minPos)

            HStack(spacing: 0) {
                RequestPane(tab: tab, activeEnvironment: activeEnvironment)
                    .frame(width: min(max(position, minPos), maxPos))

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .padding(.horizontal, 3)
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .named("splitContainer"))
                            .onChanged { value in
                                dividerPosition = min(max(value.location.x, minPos), maxPos)
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                ResponsePane(tab: tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .coordinateSpace(name: "splitContainer")
    }
}
