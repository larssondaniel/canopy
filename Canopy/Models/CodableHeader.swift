import Foundation

struct CodableHeader: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var key: String = ""
    var value: String = ""
}
