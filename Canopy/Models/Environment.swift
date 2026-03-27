import Foundation
import SwiftData

@Model
final class AppEnvironment {
    var id: UUID = UUID()
    var name: String = ""
    var variables: [String: String] = [:]
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var colorName: String = "blue"

    var environmentColor: EnvironmentColor {
        get { EnvironmentColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    init(name: String = "", variables: [String: String] = [:], sortOrder: Int = 0, color: EnvironmentColor = .blue) {
        self.name = name
        self.variables = variables
        self.sortOrder = sortOrder
        self.colorName = color.rawValue
    }
}
