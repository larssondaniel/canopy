import Foundation

enum IntrospectionError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int)
    case introspectionDisabled
    case decodingFailed(Error)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid endpoint URL."
        case .serverError(let code):
            return "Server returned status \(code)."
        case .introspectionDisabled:
            return "Introspection is disabled on this server."
        case .decodingFailed:
            return "Failed to decode introspection response."
        case .networkError(let message):
            return message
        }
    }
}

/// Fetches a GraphQL schema via the standard introspection query.
/// NOT @MainActor — networking and decoding run off the main thread.
struct IntrospectionClient: Sendable {

    // MARK: - Introspection Queries

    /// Full October 2021 spec query with includeDeprecated on args/inputFields.
    static let fullQuery = """
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types {
          ...FullType
        }
        directives {
          name
          description
          locations
          args(includeDeprecated: true) {
            ...InputValue
          }
        }
      }
    }

    fragment FullType on __Type {
      kind
      name
      description
      fields(includeDeprecated: true) {
        name
        description
        args(includeDeprecated: true) {
          ...InputValue
        }
        type {
          ...TypeRef
        }
        isDeprecated
        deprecationReason
      }
      inputFields(includeDeprecated: true) {
        ...InputValue
      }
      interfaces {
        ...TypeRef
      }
      enumValues(includeDeprecated: true) {
        name
        description
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        ...TypeRef
      }
    }

    fragment InputValue on __InputValue {
      name
      description
      type {
        ...TypeRef
      }
      defaultValue
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    /// June 2018 fallback — omits includeDeprecated on args/inputFields.
    static let legacyQuery = """
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types {
          ...FullType
        }
        directives {
          name
          description
          locations
          args {
            ...InputValue
          }
        }
      }
    }

    fragment FullType on __Type {
      kind
      name
      description
      fields(includeDeprecated: true) {
        name
        description
        args {
          ...InputValue
        }
        type {
          ...TypeRef
        }
        isDeprecated
        deprecationReason
      }
      inputFields {
        ...InputValue
      }
      interfaces {
        ...TypeRef
      }
      enumValues(includeDeprecated: true) {
        name
        description
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        ...TypeRef
      }
    }

    fragment InputValue on __InputValue {
      name
      description
      type {
        ...TypeRef
      }
      defaultValue
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    // MARK: - Fetch

    func fetchSchema(
        url: URL,
        method: HTTPMethod,
        auth: AuthConfiguration,
        headers: [CodableHeader]
    ) async throws -> GraphQLSchema {
        let (schema, _) = try await fetchSchemaWithRawData(url: url, method: method, auth: auth, headers: headers)
        return schema
    }

    /// Fetch schema and return both the decoded schema and the raw introspection JSON for caching.
    func fetchSchemaWithRawData(
        url: URL,
        method: HTTPMethod,
        auth: AuthConfiguration,
        headers: [CodableHeader]
    ) async throws -> (GraphQLSchema, Data) {
        // Try full query first, fall back to legacy on error
        do {
            return try await performIntrospection(url: url, method: method, query: Self.fullQuery, auth: auth, headers: headers)
        } catch IntrospectionError.decodingFailed {
            // Full query may have failed due to unsupported fields — try legacy
            return try await performIntrospection(url: url, method: method, query: Self.legacyQuery, auth: auth, headers: headers)
        }
    }

    private func performIntrospection(
        url: URL,
        method: HTTPMethod,
        query: String,
        auth: AuthConfiguration,
        headers: [CodableHeader]
    ) async throws -> (GraphQLSchema, Data) {
        let request = try Self.buildIntrospectionRequest(
            url: url, method: method, query: query, auth: auth, headers: headers
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw IntrospectionError.networkError(urlError.friendlyDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntrospectionError.networkError("Unexpected response type.")
        }

        guard httpResponse.statusCode == 200 else {
            // Check for introspection-disabled patterns
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
                if let body = String(data: data, encoding: .utf8),
                   body.localizedStandardContains("introspection") {
                    throw IntrospectionError.introspectionDisabled
                }
            }
            throw IntrospectionError.serverError(statusCode: httpResponse.statusCode)
        }

        // Check for GraphQL-level errors that indicate introspection is disabled
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = json["errors"] as? [[String: Any]],
           !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            if messages.contains(where: { $0.localizedStandardContains("introspection") }) {
                throw IntrospectionError.introspectionDisabled
            }
        }

        // Already off main actor (IntrospectionClient is not @MainActor), decode directly
        do {
            let decoded = try JSONDecoder().decode(IntrospectionResponse.self, from: data)
            return (GraphQLSchema.from(decoded.data.__schema), data)
        } catch {
            throw IntrospectionError.decodingFailed(error)
        }
    }

    // MARK: - Request Building

    /// Build a URLRequest for introspection. Nonisolated static so it can be called off main actor.
    static func buildIntrospectionRequest(
        url: URL,
        method: HTTPMethod,
        query: String,
        auth: AuthConfiguration,
        headers: [CodableHeader]
    ) throws -> URLRequest {
        var request: URLRequest

        switch method {
        case .post:
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            let body: [String: Any] = ["query": query]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .get:
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw IntrospectionError.invalidURL
            }
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "query", value: query))
            components.queryItems = queryItems
            guard let finalURL = components.url else {
                throw IntrospectionError.invalidURL
            }
            request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        // Auth header
        if let authHeader = auth.header {
            request.setValue(authHeader.value, forHTTPHeaderField: authHeader.name)
        }

        // Custom headers
        for header in headers where !header.key.trimmingCharacters(in: .whitespaces).isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        return request
    }

}
