import CryptoKit
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
    }

    private var schemasByEndpoint: [String: LoadState] = [:]
    private var currentFetchTask: Task<Void, Never>?

    func state(for endpoint: String) -> LoadState {
        schemasByEndpoint[endpoint, default: .idle]
    }

    /// Fetch the schema for the given endpoint using full request context.
    /// Callers provide method/auth/headers from their per-window state.
    /// Uses stale-while-revalidate: loads cache immediately, then background-refreshes.
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

        // Stale-while-revalidate: load from cache first for instant display
        if !force, case .loaded = schemasByEndpoint[normalized] {
            // Already loaded above
        } else if let cachedData = Self.loadCachedSchema(for: normalized) {
            do {
                let decoded = try JSONDecoder().decode(IntrospectionResponse.self, from: cachedData)
                let schema = GraphQLSchema.from(decoded.data.__schema)
                schemasByEndpoint[normalized] = .loaded(schema)
            } catch {
                // Corrupted cache — delete and continue to network fetch
                Self.deleteCachedSchema(for: normalized)
            }
        }

        // If we loaded from cache but it's not a force refresh, still background-refresh
        let isStaleRevalidate: Bool
        if case .loaded = schemasByEndpoint[normalized] {
            isStaleRevalidate = true
        } else {
            isStaleRevalidate = false
            schemasByEndpoint[normalized] = .loading
        }

        currentFetchTask = Task {
            let client = IntrospectionClient()
            do {
                guard let url = URL(string: normalized),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http",
                      url.host != nil else {
                    throw IntrospectionError.invalidURL
                }
                let (schema, rawData) = try await client.fetchSchemaWithRawData(
                    url: url, method: method, auth: auth, headers: headers
                )
                if !Task.isCancelled {
                    schemasByEndpoint[normalized] = .loaded(schema)
                    // Cache the raw introspection JSON off the main actor
                    let endpoint = normalized
                    Task.detached {
                        Self.cacheSchema(rawData, for: endpoint)
                    }
                }
            } catch is CancellationError {
                // Do NOT set .error — leave previous state
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Do NOT set .error — leave previous state
            } catch {
                if !Task.isCancelled && !isStaleRevalidate {
                    schemasByEndpoint[normalized] = .error(
                        error.localizedDescription
                    )
                }
                // If stale-revalidate failed, keep the cached version visible
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

    // MARK: - Schema Cache

    /// Write raw introspection JSON to Caches directory. Failures are logged but never block UI.
    nonisolated static func cacheSchema(_ data: Data, for endpoint: String) {
        guard let cacheDir = cacheDirectory() else { return }
        let fileURL = cacheDir.appendingPathComponent(cacheFilename(for: endpoint))
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache write failures are non-fatal
        }
    }

    /// Read cached introspection JSON. Returns nil on miss or corruption.
    nonisolated static func loadCachedSchema(for endpoint: String) -> Data? {
        guard let cacheDir = cacheDirectory() else { return nil }
        let fileURL = cacheDir.appendingPathComponent(cacheFilename(for: endpoint))
        return try? Data(contentsOf: fileURL)
    }

    /// Delete a corrupted cache entry.
    nonisolated static func deleteCachedSchema(for endpoint: String) {
        guard let cacheDir = cacheDirectory() else { return }
        let fileURL = cacheDir.appendingPathComponent(cacheFilename(for: endpoint))
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// The Caches directory for schema storage.
    nonisolated static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SchemaCache/v1")
    }

    /// SHA256 hex digest of the normalized endpoint URL, used as the cache filename.
    nonisolated static func cacheFilename(for endpoint: String) -> String {
        let digest = SHA256.hash(data: Data(endpoint.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }
}
