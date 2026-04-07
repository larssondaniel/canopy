import Foundation

/// Persists sidebar expand/collapse state per-endpoint using UserDefaults.
///
/// Two kinds of state are tracked:
/// 1. **Section expand state** — which operation sections (Queries, Mutations, Subscriptions) are expanded.
///    Default: only Queries expanded on first launch.
/// 2. **Field expand state** — which operation/field rows are expanded within sections.
///
/// Keys are scoped per-endpoint URL hash to keep schemas independent.
enum ExpandStateStore {

    // MARK: - Section Expand State

    static func loadExpandedSections(for endpoint: String) -> Set<OperationSegment> {
        let key = sectionKey(for: endpoint)
        guard let data = UserDefaults.standard.data(forKey: key),
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else {
            // Default: only Queries expanded
            return [.queries]
        }
        return Set(rawValues.compactMap { OperationSegment(rawValue: $0) })
    }

    static func saveExpandedSections(_ sections: Set<OperationSegment>, for endpoint: String) {
        let key = sectionKey(for: endpoint)
        let rawValues = sections.map(\.rawValue)
        if let data = try? JSONEncoder().encode(rawValues) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Field Expand State

    static func loadExpandedPaths(for endpoint: String) -> Set<String> {
        let key = pathKey(for: endpoint)
        guard let data = UserDefaults.standard.data(forKey: key),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(paths)
    }

    static func saveExpandedPaths(_ paths: Set<String>, for endpoint: String) {
        let key = pathKey(for: endpoint)
        // Cap at 500 entries to keep UserDefaults reasonable
        let capped = paths.count > 500 ? Set(paths.prefix(500)) : paths
        if let data = try? JSONEncoder().encode(Array(capped)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Remove paths that no longer exist in the schema.
    static func pruneExpandedPaths(_ paths: Set<String>, schema: GraphQLSchema) -> Set<String> {
        // Only prune root-level paths (operation names); sub-paths are cheap to keep
        let rootFields = Set(
            [schema.queryTypeName, schema.mutationTypeName, schema.subscriptionTypeName]
                .compactMap { $0 }
                .compactMap { schema.type(named: $0) }
                .flatMap { $0.fields ?? [] }
                .map(\.name)
        )
        return paths.filter { path in
            let root = path.split(separator: "/").first.map(String.init) ?? path
            return rootFields.contains(root)
        }
    }

    // MARK: - Private

    private static func sectionKey(for endpoint: String) -> String {
        "expandedSections_\(stableHash(endpoint))"
    }

    private static func pathKey(for endpoint: String) -> String {
        "expandedPaths_\(stableHash(endpoint))"
    }

    /// Stable hash that doesn't change across app launches (unlike Hashable on String).
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }
}
