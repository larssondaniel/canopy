import SwiftUI

struct ResponseBodyView: View {
    let tab: QueryTab

    var body: some View {
        ZStack {
            if let error = tab.error, tab.responseBody == nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if let responseBody = tab.responseBody {
                ScrollView {
                    Text(responseBody)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            } else {
                Text("Send a request to see the response")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if tab.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.opacity(0.5))
            }
        }
    }
}
