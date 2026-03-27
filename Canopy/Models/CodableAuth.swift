import Foundation

struct CodableAuth: Codable, Equatable {
    var type: String
    var username: String
    var password: String
    var token: String
    var headerName: String
    var headerValue: String

    init(type: String = "none", username: String = "", password: String = "", token: String = "", headerName: String = "", headerValue: String = "") {
        self.type = type
        self.username = username
        self.password = password
        self.token = token
        self.headerName = headerName
        self.headerValue = headerValue
    }

    init(authConfiguration: AuthConfiguration) {
        switch authConfiguration {
        case .none:
            self.init()
        case .basic(let username, let password):
            self.init(type: "basic", username: username, password: password)
        case .bearer(let token):
            self.init(type: "bearer", token: token)
        case .apiKey(let headerName, let value):
            self.init(type: "apiKey", headerName: headerName, headerValue: value)
        }
    }

    static let none = CodableAuth()

    func toAuthConfiguration() -> AuthConfiguration {
        switch type {
        case "basic": return .basic(username: username, password: password)
        case "bearer": return .bearer(token: token)
        case "apiKey": return .apiKey(headerName: headerName, value: headerValue)
        default: return .none
        }
    }

    var authType: AuthType {
        toAuthConfiguration().authType
    }
}
