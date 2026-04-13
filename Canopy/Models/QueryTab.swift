import Foundation
import SwiftData

@Model
final class QueryTab {
    var id: UUID = UUID()
    var name: String = "Untitled"
    var endpoint: String = ""
    var query: String = ""
    var variables: String = ""
    var method: HTTPMethod = HTTPMethod.post
    var headers: [CodableHeader] = []
    var authConfig: CodableAuth = CodableAuth.none
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    // Persisted response state
    var responseBody: String?
    var responseStatusCode: Int?
    var responseTime: TimeInterval?
    var responseSize: Int?
    var responseHeaders: [String: String]?
    var lastError: String?

    // Relationships
    var project: Project?

    // Transient state (not persisted)
    @Transient var currentTask: Task<Void, Never>? = nil
    @Transient var isLoading: Bool = false

    init() {}
}

extension QueryTab {
    func hasUnresolvedVariables(variables resolvedVars: [String: String]) -> Bool {
        guard !resolvedVars.isEmpty else { return false }

        if TemplateEngine.hasUnresolvedVariables(in: endpoint, variables: resolvedVars) { return true }
        if TemplateEngine.hasUnresolvedVariables(in: variables, variables: resolvedVars) { return true }

        for header in headers {
            if TemplateEngine.hasUnresolvedVariables(in: header.value, variables: resolvedVars) { return true }
        }

        let auth = authConfig.toAuthConfiguration()
        switch auth {
        case .bearer(let token):
            if TemplateEngine.hasUnresolvedVariables(in: token, variables: resolvedVars) { return true }
        case .apiKey(_, let value):
            if TemplateEngine.hasUnresolvedVariables(in: value, variables: resolvedVars) { return true }
        case .basic(let username, let password):
            if TemplateEngine.hasUnresolvedVariables(in: username, variables: resolvedVars) { return true }
            if TemplateEngine.hasUnresolvedVariables(in: password, variables: resolvedVars) { return true }
        case .none:
            break
        }

        return false
    }

    func unresolvedVariableNames(variables resolvedVars: [String: String]) -> [String] {
        guard !resolvedVars.isEmpty else { return [] }
        var names: [String] = []

        let fields = [endpoint, variables] + headers.map(\.value)
        for field in fields {
            for v in TemplateEngine.findVariables(in: field) where resolvedVars[v.name] == nil {
                if !names.contains(v.name) {
                    names.append(v.name)
                }
            }
        }
        return names
    }
}
