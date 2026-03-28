import Testing
import Foundation
@testable import Canopy

@Suite("CodableAuth Tests")
struct CodableAuthTests {
    @Test("Default is none")
    func defaultIsNone() {
        let auth = CodableAuth.none
        #expect(auth.type == "none")
        #expect(auth.authType == .none)
    }

    @Test("Roundtrip from AuthConfiguration - none")
    func roundtripNone() {
        let auth = CodableAuth(authConfiguration: .none)
        #expect(auth.toAuthConfiguration().authType == .none)
    }

    @Test("Roundtrip from AuthConfiguration - basic")
    func roundtripBasic() {
        let auth = CodableAuth(authConfiguration: .basic(username: "user", password: "pass"))
        let result = auth.toAuthConfiguration()
        #expect(result.authType == .basic)
        if case .basic(let u, let p) = result {
            #expect(u == "user")
            #expect(p == "pass")
        } else {
            Issue.record("Expected basic auth")
        }
    }

    @Test("Roundtrip from AuthConfiguration - bearer")
    func roundtripBearer() {
        let auth = CodableAuth(authConfiguration: .bearer(token: "my-token"))
        let result = auth.toAuthConfiguration()
        #expect(result.authType == .bearer)
        if case .bearer(let t) = result {
            #expect(t == "my-token")
        } else {
            Issue.record("Expected bearer auth")
        }
    }

    @Test("Roundtrip from AuthConfiguration - apiKey")
    func roundtripApiKey() {
        let auth = CodableAuth(authConfiguration: .apiKey(headerName: "X-Key", value: "secret"))
        let result = auth.toAuthConfiguration()
        #expect(result.authType == .apiKey)
        if case .apiKey(let name, let value) = result {
            #expect(name == "X-Key")
            #expect(value == "secret")
        } else {
            Issue.record("Expected apiKey auth")
        }
    }

    @Test("Equatable - same values are equal")
    func equatable() {
        let a = CodableAuth(type: "bearer", token: "tok")
        let b = CodableAuth(type: "bearer", token: "tok")
        #expect(a == b)
    }

    @Test("Equatable - different values are not equal")
    func notEquatable() {
        let a = CodableAuth(type: "bearer", token: "tok1")
        let b = CodableAuth(type: "bearer", token: "tok2")
        #expect(a != b)
    }
}

@Suite("CodableHeader Tests")
struct CodableHeaderTests {
    @Test("Default values are empty strings")
    func defaultValues() {
        let header = CodableHeader()
        #expect(header.key == "")
        #expect(header.value == "")
    }

    @Test("Each header has a unique ID")
    func uniqueIDs() {
        let h1 = CodableHeader()
        let h2 = CodableHeader()
        #expect(h1.id != h2.id)
    }

    @Test("Can create with custom values")
    func customValues() {
        let header = CodableHeader(key: "Authorization", value: "Bearer token123")
        #expect(header.key == "Authorization")
        #expect(header.value == "Bearer token123")
    }

    @Test("Equatable works")
    func equatable() {
        let id = UUID()
        let a = CodableHeader(id: id, key: "X", value: "Y")
        let b = CodableHeader(id: id, key: "X", value: "Y")
        #expect(a == b)
    }
}
