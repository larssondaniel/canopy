import Testing
import Foundation
@testable import Canopy

@Suite("AuthConfiguration Tests")
struct AuthConfigurationTests {

    @Test("None produces no header")
    func noneHeader() {
        let config = AuthConfiguration.none
        #expect(config.header == nil)
    }

    @Test("None has correct auth type")
    func noneAuthType() {
        #expect(AuthConfiguration.none.authType == .none)
    }

    @Test("Basic auth produces correct Authorization header")
    func basicHeader() {
        let config = AuthConfiguration.basic(username: "user", password: "pass")
        let header = config.header
        #expect(header?.name == "Authorization")
        // "user:pass" in base64 is "dXNlcjpwYXNz"
        #expect(header?.value == "Basic dXNlcjpwYXNz")
    }

    @Test("Basic auth with empty password is valid")
    func basicEmptyPassword() {
        let config = AuthConfiguration.basic(username: "user", password: "")
        let header = config.header
        #expect(header != nil)
        // "user:" in base64 is "dXNlcjo="
        #expect(header?.value == "Basic dXNlcjo=")
    }

    @Test("Basic auth with empty username is valid")
    func basicEmptyUsername() {
        let config = AuthConfiguration.basic(username: "", password: "pass")
        let header = config.header
        #expect(header != nil)
        // ":pass" in base64 is "OnBhc3M="
        #expect(header?.value == "Basic OnBhc3M=")
    }

    @Test("Basic auth with both empty is valid")
    func basicBothEmpty() {
        let config = AuthConfiguration.basic(username: "", password: "")
        let header = config.header
        #expect(header != nil)
        // ":" in base64 is "Og=="
        #expect(header?.value == "Basic Og==")
    }

    @Test("Basic auth handles UTF-8 characters")
    func basicUTF8() {
        let config = AuthConfiguration.basic(username: "café", password: "päss")
        let header = config.header
        #expect(header != nil)
        let expected = Data("café:päss".utf8).base64EncodedString()
        #expect(header?.value == "Basic \(expected)")
    }

    @Test("Basic auth has correct auth type")
    func basicAuthType() {
        let config = AuthConfiguration.basic(username: "u", password: "p")
        #expect(config.authType == .basic)
    }

    @Test("Bearer produces correct Authorization header")
    func bearerHeader() {
        let config = AuthConfiguration.bearer(token: "my-token-123")
        let header = config.header
        #expect(header?.name == "Authorization")
        #expect(header?.value == "Bearer my-token-123")
    }

    @Test("Bearer with empty token produces no header")
    func bearerEmptyToken() {
        let config = AuthConfiguration.bearer(token: "")
        #expect(config.header == nil)
    }

    @Test("Bearer with whitespace-only token produces no header")
    func bearerWhitespaceToken() {
        let config = AuthConfiguration.bearer(token: "   \n  ")
        #expect(config.header == nil)
    }

    @Test("Bearer trims whitespace from token")
    func bearerTrimmed() {
        let config = AuthConfiguration.bearer(token: "  my-token  ")
        #expect(config.header?.value == "Bearer my-token")
    }

    @Test("Bearer has correct auth type")
    func bearerAuthType() {
        let config = AuthConfiguration.bearer(token: "t")
        #expect(config.authType == .bearer)
    }

    @Test("API Key produces correct custom header")
    func apiKeyHeader() {
        let config = AuthConfiguration.apiKey(headerName: "X-API-Key", value: "secret123")
        let header = config.header
        #expect(header?.name == "X-API-Key")
        #expect(header?.value == "secret123")
    }

    @Test("API Key with empty header name produces no header")
    func apiKeyEmptyName() {
        let config = AuthConfiguration.apiKey(headerName: "", value: "secret")
        #expect(config.header == nil)
    }

    @Test("API Key with empty value produces no header")
    func apiKeyEmptyValue() {
        let config = AuthConfiguration.apiKey(headerName: "X-API-Key", value: "")
        #expect(config.header == nil)
    }

    @Test("API Key with whitespace-only name produces no header")
    func apiKeyWhitespaceName() {
        let config = AuthConfiguration.apiKey(headerName: "   ", value: "secret")
        #expect(config.header == nil)
    }

    @Test("API Key with whitespace-only value produces no header")
    func apiKeyWhitespaceValue() {
        let config = AuthConfiguration.apiKey(headerName: "X-API-Key", value: "   ")
        #expect(config.header == nil)
    }

    @Test("API Key has correct auth type")
    func apiKeyAuthType() {
        let config = AuthConfiguration.apiKey(headerName: "X-API-Key", value: "v")
        #expect(config.authType == .apiKey)
    }
}
