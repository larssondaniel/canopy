import SwiftUI

enum URLSegment {
    case text(String)
    case resolvedVariable(name: String, value: String)
    case unresolvedVariable(rawText: String)
}

struct TokenizedURLDisplay: View {
    let url: String
    let placeholder: String
    let variables: [String: String]

    var body: some View {
        if url.isEmpty {
            Text(placeholder)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let segs = Self.segments(from: url, variables: variables)
            HStack(spacing: 0) {
                ForEach(Array(segs.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: URLSegment) -> some View {
        switch segment {
        case .text(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))

        case .resolvedVariable(let name, let value):
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
                .help("\(name) \u{2192} \(value)")

        case .unresolvedVariable(let rawText):
            Text(rawText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    static func segments(from url: String, variables: [String: String]) -> [URLSegment] {
        let templateVars = TemplateEngine.findVariables(in: url)
        guard !templateVars.isEmpty else {
            return [.text(url)]
        }

        var result: [URLSegment] = []
        var currentIndex = url.startIndex

        for templateVar in templateVars {
            if currentIndex < templateVar.range.lowerBound {
                let plain = String(url[currentIndex..<templateVar.range.lowerBound])
                result.append(.text(plain))
            }

            if let value = variables[templateVar.name] {
                result.append(.resolvedVariable(name: templateVar.name, value: value))
            } else {
                let raw = String(url[templateVar.range])
                result.append(.unresolvedVariable(rawText: raw))
            }

            currentIndex = templateVar.range.upperBound
        }

        if currentIndex < url.endIndex {
            let trailing = String(url[currentIndex..<url.endIndex])
            result.append(.text(trailing))
        }

        return result
    }
}
