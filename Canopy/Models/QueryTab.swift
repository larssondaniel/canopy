import Foundation
import Observation

@Observable
final class QueryTab: Identifiable {
    let id = UUID()
    var name: String = "Untitled"
    var endpoint: String = ""
    var query: String = ""
    var variables: String = ""
    var method: HTTPMethod = .post
    var headers: [HeaderEntry] = []

    // Response state
    var responseBody: String?
    var responseStatusCode: Int?
    var responseTime: TimeInterval?
    var responseSize: Int?
    var responseHeaders: [String: String]?
    var isLoading: Bool = false
    var error: String?

    // In-flight request tracking
    var currentTask: Task<Void, Never>?
}
