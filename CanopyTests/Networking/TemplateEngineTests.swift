import Testing
import Foundation
@testable import Canopy

@Suite("TemplateEngine Tests")
struct TemplateEngineTests {

    // MARK: - findVariables

    @Test("Finds single variable")
    func findSingleVariable() {
        let vars = TemplateEngine.findVariables(in: "{{host}}")
        #expect(vars.count == 1)
        #expect(vars.first?.name == "host")
    }

    @Test("Finds multiple variables")
    func findMultipleVariables() {
        let vars = TemplateEngine.findVariables(in: "{{protocol}}://{{host}}/{{path}}")
        #expect(vars.count == 3)
        #expect(vars.map(\.name) == ["protocol", "host", "path"])
    }

    @Test("Handles whitespace inside braces")
    func whitespaceInsideBraces() {
        let vars = TemplateEngine.findVariables(in: "{{ host }}")
        #expect(vars.count == 1)
        #expect(vars.first?.name == "host")
    }

    @Test("Ignores empty braces")
    func emptyBraces() {
        let vars = TemplateEngine.findVariables(in: "{{}}")
        #expect(vars.isEmpty)
    }

    @Test("Ignores unclosed braces")
    func unclosedBraces() {
        let vars = TemplateEngine.findVariables(in: "{{unclosed")
        #expect(vars.isEmpty)
    }

    @Test("Ignores single braces")
    func singleBraces() {
        let vars = TemplateEngine.findVariables(in: "{single}")
        #expect(vars.isEmpty)
    }

    @Test("No variables in plain text")
    func noVariablesInPlainText() {
        let vars = TemplateEngine.findVariables(in: "https://api.example.com/graphql")
        #expect(vars.isEmpty)
    }

    @Test("Finds variables with underscores and numbers")
    func variableNamingConventions() {
        let vars = TemplateEngine.findVariables(in: "{{api_url_v2}} {{_private}}")
        #expect(vars.count == 2)
        #expect(vars.map(\.name) == ["api_url_v2", "_private"])
    }

    @Test("Returns empty for empty input")
    func emptyInput() {
        let vars = TemplateEngine.findVariables(in: "")
        #expect(vars.isEmpty)
    }

    // MARK: - substitute

    @Test("Basic substitution")
    func basicSubstitution() {
        let result = TemplateEngine.substitute(in: "{{host}}", variables: ["host": "localhost"])
        #expect(result.resolvedText == "localhost")
        #expect(result.unresolvedVariables.isEmpty)
    }

    @Test("Multiple variables in one string")
    func multipleSubstitution() {
        let result = TemplateEngine.substitute(
            in: "{{protocol}}://{{host}}:{{port}}",
            variables: ["protocol": "https", "host": "api.example.com", "port": "8080"]
        )
        #expect(result.resolvedText == "https://api.example.com:8080")
        #expect(result.unresolvedVariables.isEmpty)
    }

    @Test("Undefined variable left as literal and flagged")
    func undefinedVariable() {
        let result = TemplateEngine.substitute(in: "{{missing}}", variables: [:])
        #expect(result.resolvedText == "{{missing}}")
        #expect(result.unresolvedVariables == ["missing"])
    }

    @Test("Mix of resolved and unresolved")
    func mixedResolution() {
        let result = TemplateEngine.substitute(
            in: "{{host}}/{{path}}",
            variables: ["host": "example.com"]
        )
        #expect(result.resolvedText == "example.com/{{path}}")
        #expect(result.unresolvedVariables == ["path"])
    }

    @Test("Whitespace trimming in substitution")
    func whitespaceTrimming() {
        let result = TemplateEngine.substitute(in: "{{ host }}", variables: ["host": "localhost"])
        #expect(result.resolvedText == "localhost")
    }

    @Test("Plain text passes through unchanged")
    func plainTextPassthrough() {
        let result = TemplateEngine.substitute(in: "no variables here", variables: ["key": "value"])
        #expect(result.resolvedText == "no variables here")
        #expect(result.unresolvedVariables.isEmpty)
    }

    @Test("Empty input returns empty")
    func emptyInputSubstitution() {
        let result = TemplateEngine.substitute(in: "", variables: ["key": "value"])
        #expect(result.resolvedText == "")
        #expect(result.unresolvedVariables.isEmpty)
    }

    @Test("Special characters in values")
    func specialCharactersInValues() {
        let result = TemplateEngine.substitute(
            in: "{{url}}",
            variables: ["url": "https://api.example.com/v1?key=val&other=true"]
        )
        #expect(result.resolvedText == "https://api.example.com/v1?key=val&other=true")
    }

    @Test("Value with quotes substitutes correctly")
    func quotesInValues() {
        let result = TemplateEngine.substitute(
            in: "{{value}}",
            variables: ["value": "he said \"hello\""]
        )
        #expect(result.resolvedText == "he said \"hello\"")
    }

    @Test("Empty variables dictionary")
    func emptyVariablesDictionary() {
        let result = TemplateEngine.substitute(in: "{{var}}", variables: [:])
        #expect(result.resolvedText == "{{var}}")
        #expect(result.unresolvedVariables == ["var"])
    }

    @Test("Duplicate variable references")
    func duplicateVariableReferences() {
        let result = TemplateEngine.substitute(
            in: "{{host}}/{{host}}",
            variables: ["host": "example.com"]
        )
        #expect(result.resolvedText == "example.com/example.com")
    }

    @Test("Variable value can be empty string")
    func emptyStringValue() {
        let result = TemplateEngine.substitute(in: "prefix-{{var}}-suffix", variables: ["var": ""])
        #expect(result.resolvedText == "prefix--suffix")
        #expect(result.unresolvedVariables.isEmpty)
    }

    // MARK: - hasUnresolvedVariables

    @Test("Returns false when all variables resolved")
    func allResolved() {
        let result = TemplateEngine.hasUnresolvedVariables(in: "{{host}}", variables: ["host": "localhost"])
        #expect(result == false)
    }

    @Test("Returns true when variable is undefined")
    func hasUndefined() {
        let result = TemplateEngine.hasUnresolvedVariables(in: "{{missing}}", variables: [:])
        #expect(result == true)
    }

    @Test("Returns false for plain text")
    func plainTextNoUnresolved() {
        let result = TemplateEngine.hasUnresolvedVariables(in: "no vars", variables: [:])
        #expect(result == false)
    }

    @Test("Returns false for empty input")
    func emptyInputNoUnresolved() {
        let result = TemplateEngine.hasUnresolvedVariables(in: "", variables: ["key": "value"])
        #expect(result == false)
    }

    @Test("Returns true when only some variables resolved")
    func partiallyResolved() {
        let result = TemplateEngine.hasUnresolvedVariables(
            in: "{{a}}/{{b}}",
            variables: ["a": "resolved"]
        )
        #expect(result == true)
    }
}
