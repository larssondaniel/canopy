import SwiftUI

enum EnvironmentColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }
}
