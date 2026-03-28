import Foundation

enum ContentTab: Identifiable, Hashable {
    case query(UUID)
    case environments

    var id: String {
        switch self {
        case .query(let uuid): "query-\(uuid.uuidString)"
        case .environments: "environments"
        }
    }

    var isEnvironments: Bool {
        if case .environments = self { return true }
        return false
    }

    var queryID: UUID? {
        if case .query(let uuid) = self { return uuid }
        return nil
    }
}
