import Foundation

struct Variable: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}
