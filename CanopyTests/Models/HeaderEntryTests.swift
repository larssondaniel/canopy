import Testing
@testable import Canopy

@Suite("HeaderEntry Tests")
struct HeaderEntryTests {
    @Test("Default values are empty strings")
    func defaultValues() {
        let entry = HeaderEntry()
        #expect(entry.key == "")
        #expect(entry.value == "")
    }

    @Test("Each entry has a unique ID")
    func uniqueIDs() {
        let entry1 = HeaderEntry()
        let entry2 = HeaderEntry()
        #expect(entry1.id != entry2.id)
    }

    @Test("Can create with custom values")
    func customValues() {
        var entry = HeaderEntry()
        entry.key = "Authorization"
        entry.value = "Bearer token123"
        #expect(entry.key == "Authorization")
        #expect(entry.value == "Bearer token123")
    }
}
