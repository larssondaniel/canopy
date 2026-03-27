import Foundation
import SwiftData

@Model
final class AppEnvironment {
    var id: UUID = UUID()
    var name: String = ""
    var variables: [String: String] = [:]
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(name: String = "", variables: [String: String] = [:], sortOrder: Int = 0) {
        self.name = name
        self.variables = variables
        self.sortOrder = sortOrder
    }
}
