import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var endpointPattern: String = "{{host}}"
    var defaultVariables: [Variable] = []
    var environments: [ProjectEnvironment] = []
    var activeEnvironmentId: UUID?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \QueryTab.project)
    var queryTabs: [QueryTab] = []

    init(
        name: String = "",
        endpointPattern: String = "{{host}}",
        defaultVariables: [Variable] = [],
        activeEnvironmentId: UUID? = nil
    ) {
        self.name = name
        self.endpointPattern = endpointPattern
        self.defaultVariables = defaultVariables
        self.activeEnvironmentId = activeEnvironmentId
    }

    /// Resolves variables using defaults-with-overrides cascade.
    /// Empty values fall through to the next layer.
    func resolvedVariables() -> [String: String] {
        var result: [String: String] = [:]

        // 1. Start with defaults (non-empty only)
        for v in defaultVariables where !v.value.isEmpty {
            result[v.key] = v.value
        }

        // 2. Override with active environment (non-empty only)
        if let envId = activeEnvironmentId,
           let env = environments.first(where: { $0.id == envId }) {
            for v in env.variables where !v.value.isEmpty {
                result[v.key] = v.value
            }
        }

        return result
    }

    /// The currently active environment, if any.
    var activeEnvironment: ProjectEnvironment? {
        guard let envId = activeEnvironmentId else { return nil }
        return environments.first { $0.id == envId }
    }

    /// Deletes an environment, clearing activeEnvironmentId if it was active.
    func deleteEnvironment(_ environment: ProjectEnvironment, context: ModelContext) {
        if activeEnvironmentId == environment.id {
            activeEnvironmentId = nil
        }
        context.delete(environment)
    }
}
