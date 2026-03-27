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
