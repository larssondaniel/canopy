import SwiftUI

struct ResponsePane: View {
    let tab: QueryTab

    var body: some View {
        VStack(spacing: 0) {
            ResponseMetadataBar(tab: tab)
            Divider()
            ResponseBodyView(tab: tab)
            if let responseHeaders = tab.responseHeaders {
                Divider()
                ResponseHeadersView(headers: responseHeaders)
            }
        }
    }
}
