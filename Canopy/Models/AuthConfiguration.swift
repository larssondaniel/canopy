import Foundation

enum AuthType: String, CaseIterable {
    case none = "None"
    case basic = "Basic Auth"
    case bearer = "Bearer Token"
    case apiKey = "API Key"
}

enum AuthConfiguration {
    case none
    case basic(username: String, password: String)
    case bearer(token: String)
    case apiKey(headerName: String, value: String)

    var authType: AuthType {
        switch self {
        case .none: .none
        case .basic: .basic
        case .bearer: .bearer
        case .apiKey: .apiKey
        }
    }

    /// Returns the auth header as a (name, value) tuple, or nil if no header should be injected.
    var header: (name: String, value: String)? {
        switch self {
        case .none:
            return nil

        case .basic(let username, let password):
            let credentials = "\(username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            return ("Authorization", "Basic \(encoded)")

        case .bearer(let token):
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ("Authorization", "Bearer \(trimmed)")

        case .apiKey(let headerName, let value):
            let trimmedName = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedValue.isEmpty else { return nil }
            return (trimmedName, trimmedValue)
        }
    }
}
