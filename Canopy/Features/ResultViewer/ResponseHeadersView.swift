import SwiftUI

struct ResponseHeadersView: View {
    let headers: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key)
                        .fontWeight(.medium)
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 300)
        .padding(.vertical, 8)
    }
}
