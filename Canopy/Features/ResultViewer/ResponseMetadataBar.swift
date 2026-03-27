import SwiftUI

struct ResponseMetadataBar: View {
    let tab: QueryTab

    var body: some View {
        if tab.isLoading || tab.responseStatusCode != nil {
            HStack(spacing: 16) {
                if tab.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                } else if let statusCode = tab.responseStatusCode {
                    Text("\(statusCode)")
                        .foregroundStyle(statusColor(for: statusCode))
                        .fontWeight(.semibold)
                }

                if let time = tab.responseTime {
                    Text(formatTime(time))
                        .foregroundStyle(.secondary)
                }

                if let size = tab.responseSize {
                    Text(formatSize(size))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func statusColor(for code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 400..<600: return .red
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
