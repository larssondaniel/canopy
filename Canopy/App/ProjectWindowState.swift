import Foundation
import Observation

@Observable
@MainActor
final class ProjectWindowState {
    var showEnvironments = false
    var activeQueryTab: QueryTab?
    var activeEndpoint: String?
    var activeMethod: HTTPMethod = .post
    var activeAuth: CodableAuth = .init()
    var activeHeaders: [CodableHeader] = []
}
