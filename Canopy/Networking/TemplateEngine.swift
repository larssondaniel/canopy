import Foundation

struct TemplateVariable: Equatable {
    let name: String
    let range: Range<String.Index>

    static func == (lhs: TemplateVariable, rhs: TemplateVariable) -> Bool {
        lhs.name == rhs.name && lhs.range == rhs.range
    }
}

struct SubstitutionResult: Equatable {
    let resolvedText: String
    let unresolvedVariables: [String]
}

enum TemplateEngine {

    /// Regex pattern: `{{` optional whitespace, capture group of valid identifier, optional whitespace, `}}`
    private static let pattern = try! NSRegularExpression(
        pattern: #"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}"#
    )

    /// Returns all `{{name}}` references with their names and ranges.
    static func findVariables(in text: String) -> [TemplateVariable] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: nsRange)

        return matches.compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range, in: text) else {
                return nil
            }
            let name = String(text[nameRange])
            return TemplateVariable(name: name, range: fullRange)
        }
    }

    /// Substitutes `{{variable}}` references with values from the provided dictionary.
    /// Undefined variables are left as literals and tracked in `unresolvedVariables`.
    static func substitute(in text: String, variables: [String: String]) -> SubstitutionResult {
        let templateVars = findVariables(in: text)
        guard !templateVars.isEmpty else {
            return SubstitutionResult(resolvedText: text, unresolvedVariables: [])
        }

        var resolved = text
        var unresolved: [String] = []

        // Process in reverse order to preserve ranges
        for templateVar in templateVars.reversed() {
            if let value = variables[templateVar.name] {
                resolved.replaceSubrange(templateVar.range, with: value)
            } else {
                if !unresolved.contains(templateVar.name) {
                    unresolved.append(templateVar.name)
                }
            }
        }

        return SubstitutionResult(resolvedText: resolved, unresolvedVariables: unresolved.reversed())
    }

    /// Fast check: returns true if the text contains any `{{variable}}` references
    /// that are not defined in the given variables dictionary.
    static func hasUnresolvedVariables(in text: String, variables: [String: String]) -> Bool {
        let templateVars = findVariables(in: text)
        return templateVars.contains { variables[$0.name] == nil }
    }
}
