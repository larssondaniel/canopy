import Foundation

struct GraphQLResponse {
    let body: Data
    let statusCode: Int
    let elapsedTime: TimeInterval
    let responseHeaders: [String: String]

    var bodyString: String {
        String(data: body, encoding: .utf8) ?? ""
    }

    var byteSize: Int {
        body.count
    }
}
