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

    // Transient state (not persisted)
    @Transient var currentTask: Task<Void, Never>? = nil
    @Transient var isLoading: Bool = false

    init() {}
}

extension QueryTab {
    func hasUnresolvedVariables(environment: AppEnvironment?) -> Bool {
        guard let env = environment else { return false }
        let vars = env.variables

        if TemplateEngine.hasUnresolvedVariables(in: endpoint, variables: vars) { return true }
        if TemplateEngine.hasUnresolvedVariables(in: variables, variables: vars) { return true }

        for header in headers {
            if TemplateEngine.hasUnresolvedVariables(in: header.value, variables: vars) { return true }
        }

        let auth = authConfig.toAuthConfiguration()
        switch auth {
        case .bearer(let token):
            if TemplateEngine.hasUnresolvedVariables(in: token, variables: vars) { return true }
        case .apiKey(_, let value):
            if TemplateEngine.hasUnresolvedVariables(in: value, variables: vars) { return true }
        case .basic(let username, let password):
            if TemplateEngine.hasUnresolvedVariables(in: username, variables: vars) { return true }
            if TemplateEngine.hasUnresolvedVariables(in: password, variables: vars) { return true }
        case .none:
            break
        }

        return false
    }

    func unresolvedVariableNames(environment: AppEnvironment?) -> [String] {
        guard let env = environment else { return [] }
        let vars = env.variables
        var names: [String] = []

        let fields = [endpoint, variables] + headers.map(\.value)
        for field in fields {
            for v in TemplateEngine.findVariables(in: field) where vars[v.name] == nil {
                if !names.contains(v.name) {
                    names.append(v.name)
                }
            }
        }
        return names
    }
}
