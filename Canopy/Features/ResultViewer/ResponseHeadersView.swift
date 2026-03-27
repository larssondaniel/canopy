import SwiftUI

struct ResponseHeadersView: View {
    let headers: [String: String]

    var body: some View {
        if !headers.isEmpty {
            DisclosureGroup("Response Headers") {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key)
                            .fontWeight(.medium)
                        Spacer()
                        Text(value)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}
