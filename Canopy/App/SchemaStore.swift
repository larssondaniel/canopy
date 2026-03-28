import Foundation
import Observation

@Observable
@MainActor
final class SchemaStore {

    enum LoadState: Sendable {
        case idle
        case loading
        case loaded(GraphQLSchema)
        case error(String)

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }

    private(set) var schemasByEndpoint: [String: LoadState] = [:]
    /// The endpoint the sidebar should display. Set explicitly on tab switch,
    /// query success, or manual refresh — NOT computed from the live text field.
    private(set) var activeEndpoint: String?
    /// Cached request context for the active endpoint, so "Load Schema" / "Refresh"
    /// buttons can fetch without needing access to the tab.
    private var activeMethod: HTTPMethod = .post
    private var activeAuth: AuthConfiguration = .none
    private var activeHeaders: [CodableHeader] = []
    private var currentFetchTask: Task<Void, Never>?

    func state(for endpoint: String) -> LoadState {
        schemasByEndpoint[endpoint, default: .idle]
    }

    /// Update the active endpoint and its request context. Called on tab switch and query success.
    func setActiveEndpoint(
        _ endpoint: String?,
        method: HTTPMethod = .post,
        auth: AuthConfiguration = .none,
        headers: [CodableHeader] = []
    ) {
        if let endpoint {
            activeEndpoint = Self.normalizeEndpoint(endpoint)
        } else {
            activeEndpoint = nil
        }
        activeMethod = method
        activeAuth = auth
        activeHeaders = headers
    }

    /// Fetch schema using stored request context. Used by sidebar buttons.
    func fetchSchema(endpoint: String, force: Bool = false) {
        fetchSchema(
            endpoint: endpoint,
            method: activeMethod,
            auth: activeAuth,
            headers: activeHeaders,
            force: force
        )
    }

    /// Fetch the schema for the given endpoint. Skips if already loaded unless force is true.
    func fetchSchema(
        endpoint: String,
        method: HTTPMethod,
        auth: AuthConfiguration,
        headers: [CodableHeader],
        force: Bool = false
    ) {
        let normalized = Self.normalizeEndpoint(endpoint)
        if !force, case .loaded = schemasByEndpoint[normalized] {
            return
        }

        currentFetchTask?.cancel()
        schemasByEndpoint[normalized] = .loading

        currentFetchTask = Task {
            let client = IntrospectionClient()
            do {
                guard let url = URL(string: normalized),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http",
                      url.host != nil else {
                    throw IntrospectionError.invalidURL
                }
                let schema = try await client.fetchSchema(
                    url: url, method: method, auth: auth, headers: headers
                )
                if !Task.isCancelled {
                    schemasByEndpoint[normalized] = .loaded(schema)
                }
            } catch is CancellationError {
                // Do NOT set .error — leave previous state
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Do NOT set .error — leave previous state
            } catch {
                if !Task.isCancelled {
                    schemasByEndpoint[normalized] = .error(
                        error.localizedDescription
                    )
                }
            }
        }
    }

    /// Normalize an endpoint URL for consistent cache keying.
    nonisolated static func normalizeEndpoint(_ endpoint: String) -> String {
        guard var components = URLComponents(string: endpoint) else { return endpoint }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        // Remove trailing slash from path
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }
        return components.string ?? endpoint
    }
}
