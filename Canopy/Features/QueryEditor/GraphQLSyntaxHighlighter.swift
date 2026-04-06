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

    /// Remove error underline temporary attributes from the entire text range.
    static func clearErrors(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard fullRange.length > 0 else { return }
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
    }

    /// Apply error underline temporary attributes for the given ranges.
    static func applyErrors(_ errors: [QueryValidator.ValidationError], to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let textLength = (textView.string as NSString).length
        let underlineStyle = NSUnderlineStyle.patternDot.union(.single)

        for error in errors {
            guard error.range.location >= 0,
                  NSMaxRange(error.range) <= textLength else { continue }
            layoutManager.addTemporaryAttribute(.underlineStyle, value: underlineStyle.rawValue, forCharacterRange: error.range)
            layoutManager.addTemporaryAttribute(.underlineColor, value: NSColor.systemRed, forCharacterRange: error.range)
        }
    }
}
