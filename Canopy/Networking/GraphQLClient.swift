import Foundation

@MainActor
struct GraphQLClient {

    func send(tab: QueryTab, environmentVariables: [String: String]? = nil) async {
        tab.lastError = nil
        tab.isLoading = true
        defer { tab.isLoading = false }

        // Validate URL
        guard let url = URL(string: tab.endpoint), url.scheme != nil, url.host != nil else {
            tab.lastError = "Invalid URL. Please enter a valid endpoint."
            return
        }

        // Parse variables JSON if non-empty
        let trimmedVars = tab.variables.trimmingCharacters(in: .whitespacesAndNewlines)
        var variablesObject: Any?
        if !trimmedVars.isEmpty {
            guard let data = trimmedVars.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                tab.lastError = "Invalid JSON in variables."
                return
            }
            variablesObject = json
        }

        // Build request
        let auth = tab.authConfig.toAuthConfiguration()
        var request: URLRequest
        do {
            request = try buildRequest(url: url, method: tab.method, query: tab.query, variables: variablesObject, auth: auth, headers: tab.headers)
        } catch {
            tab.lastError = "Failed to build request: \(error.localizedDescription)"
            return
        }

        // Send request
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            guard let httpResponse = response as? HTTPURLResponse else {
                tab.lastError = "Unexpected response type."
                return
            }

            tab.responseStatusCode = httpResponse.statusCode
            tab.responseTime = elapsed
            tab.responseSize = data.count
            tab.responseHeaders = Dictionary(
                uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                    guard let k = key as? String, let v = value as? String else { return nil }
                    return (k, v)
                }
            )
            tab.responseBody = prettyPrintJSON(data) ?? String(data: data, encoding: .utf8) ?? ""
            tab.lastError = nil
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Request was cancelled -- don't overwrite state
            return
        } catch is CancellationError {
            return
        } catch let urlError as URLError {
            tab.responseTime = CFAbsoluteTimeGetCurrent() - start
            tab.lastError = friendlyError(for: urlError)
        } catch {
            tab.responseTime = CFAbsoluteTimeGetCurrent() - start
            tab.lastError = error.localizedDescription
        }
    }

    // MARK: - Request Building

    func buildRequest(url: URL, method: HTTPMethod, query: String, variables: Any?, auth: AuthConfiguration, headers: [CodableHeader]) throws -> URLRequest {
        var request: URLRequest

        switch method {
        case .post:
            request = URLRequest(url: url)
            request.httpMethod = "POST"

            var body: [String: Any] = ["query": query]
            if let variables {
                body["variables"] = variables
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .get:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "query", value: query))
            if let variables {
                let varsData = try JSONSerialization.data(withJSONObject: variables)
                queryItems.append(URLQueryItem(name: "variables", value: String(data: varsData, encoding: .utf8)))
            }
            components.queryItems = queryItems
            request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
        }

        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Auth headers (override defaults, overridden by user headers)
        if let authHeader = auth.header {
            request.setValue(authHeader.value, forHTTPHeaderField: authHeader.name)
        }

        // User-defined headers override defaults and auth
        for header in headers where !header.key.trimmingCharacters(in: .whitespaces).isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        return request
    }

    // MARK: - Formatting

    private func prettyPrintJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func friendlyError(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .timedOut:
            return "Request timed out."
        case .cannotFindHost:
            return "Cannot find host. Check the URL."
        case .cannotConnectToHost:
            return "Cannot connect to host."
        case .secureConnectionFailed:
            return "Secure connection failed."
        case .dnsLookupFailed:
            return "DNS lookup failed. Check the URL."
        default:
            return "Network error: \(error.localizedDescription)"
        }
    }
}
