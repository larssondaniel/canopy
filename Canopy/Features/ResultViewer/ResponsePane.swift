import SwiftUI

struct ResponsePane: View {
    let tab: QueryTab

    var body: some View {
        VStack(spacing: 0) {
            ResponseBodyView(tab: tab)
            Divider()
            ResponseMetadataBar(tab: tab)
        }
    }
}
