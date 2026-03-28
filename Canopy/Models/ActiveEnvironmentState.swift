import Foundation
import SwiftData

@Model
final class ActiveEnvironmentState {
    var id: UUID = UUID()
    var activeEnvironmentID: UUID?

    init(activeEnvironmentID: UUID? = nil) {
        self.activeEnvironmentID = activeEnvironmentID
    }
}
