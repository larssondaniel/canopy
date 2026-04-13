import Foundation
import SwiftData

@Model
final class ProjectEnvironment {
    var id: UUID = UUID()
    var name: String = ""
    var variables: [Variable] = []
    var colorName: String = "blue"
    var sortOrder: Int = 0
    var project: Project?

    var environmentColor: EnvironmentColor {
        get { EnvironmentColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    init(
        name: String = "",
        variables: [Variable] = [],
        sortOrder: Int = 0,
        color: EnvironmentColor = .blue
    ) {
        self.name = name
        self.variables = variables
        self.sortOrder = sortOrder
        self.colorName = color.rawValue
    }
}
