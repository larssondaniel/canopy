import SwiftUI

struct ResponseMetadataBar: View {
    let tab: QueryTab

    @State private var showHeaders = false

    var body: some View {
        if tab.isLoading || tab.responseStatusCode != nil {
            HStack(spacing: 8) {
                if tab.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                } else if let statusCode = tab.responseStatusCode {
                    Text("\(statusCode)")
                        .foregroundStyle(statusColor(for: statusCode))
                        .fontWeight(.bold)

                    if let time = tab.responseTime {
                        Text("·").foregroundStyle(.secondary)
                        Text(formatTime(time))
                            .foregroundStyle(.secondary)
                    }

                    if let size = tab.responseSize {
                        Text("·").foregroundStyle(.secondary)
                        Text(formatSize(size))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if graphqlErrorCount > 0 {
                    Text("\(graphqlErrorCount) error\(graphqlErrorCount == 1 ? "" : "s")")
                        .foregroundStyle(.red)
                    Text("·").foregroundStyle(.secondary)
                }

                if let headers = tab.responseHeaders, !headers.isEmpty {
                    Button {
                        showHeaders.toggle()
                    } label: {
                        HStack(spacing: 2) {
                            Text("Headers")
                            Image(systemName: showHeaders ? "chevron.up" : "chevron.down")
                                .imageScale(.small)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHeaders, arrowEdge: .bottom) {
                        ResponseHeadersView(headers: headers)
                    }
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var graphqlErrorCount: Int {
        guard let body = tab.responseBody,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [Any] else { return 0 }
        return errors.count
    }

    private func statusColor(for code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .primary
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "\(Int(interval * 1000)) ms"
        }
        return String(format: "%.2f s", interval)
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}
