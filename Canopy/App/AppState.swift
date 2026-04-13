import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class AppState {
    var modelContext: ModelContext?
}
