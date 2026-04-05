import AppKit

enum GraphQLSyntaxHighlighter {

    // MARK: - Token Colors

    private enum Colors {
        static let keyword = NSColor.systemPink        // query, mutation, fragment, on, true, false, null
        static let comment = NSColor.systemGray        // # comments
        static let string = NSColor.systemGreen        // "strings" and """block strings"""
        static let variable = NSColor.systemOrange     // $variableName
        static let directive = NSColor.systemYellow    // @include, @skip
        static let number = NSColor.systemCyan         // 42, 3.14
        static let typeName = NSColor.systemTeal       // type names after : or on
        static let punctuation = NSColor.secondaryLabelColor // { } ( ) : ! ...
    }

    // MARK: - Patterns (compiled once)

    private static let patterns: [(regex: NSRegularExpression, color: NSColor)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [])
        }
        return [
            // Block strings must come before regular strings
            (regex(#"""""[\s\S]*?""""#), Colors.string),
            // Regular strings
            (regex(#""[^"\\]*(?:\\.[^"\\]*)*""#), Colors.string),
            // Comments
            (regex(#"#[^\n]*"#), Colors.comment),
            // Keywords
            (regex(#"\b(query|mutation|subscription|fragment|on|type|interface|union|enum|input|scalar|extend|directive|schema|implements|repeatable|true|false|null)\b"#), Colors.keyword),
            // Variables
            (regex(#"\$[_A-Za-z][_0-9A-Za-z]*"#), Colors.variable),
            // Directives
            (regex(#"@[_A-Za-z][_0-9A-Za-z]*"#), Colors.directive),
            // Numbers (int and float)
            (regex(#"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#), Colors.number),
        ]
    }()

    // MARK: - Public API

    static func highlight(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }

        let string = textView.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard fullRange.length > 0 else {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            return
        }

        // Clear existing highlights and reapply
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        for (regex, color) in patterns {
            regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
            }
        }
    }
}
