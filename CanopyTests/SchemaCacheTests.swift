import Testing
import Foundation
@testable import Canopy

@Suite("Schema Cache Tests")
struct SchemaCacheTests {

    private let testEndpoint = "https://api.example.com/graphql"

    private var sampleIntrospectionJSON: Data {
        let json = """
        {
          "data": {
            "__schema": {
              "queryType": { "name": "Query" },
              "mutationType": null,
              "subscriptionType": null,
              "types": [
                {
                  "kind": "OBJECT",
                  "name": "Query",
                  "description": null,
                  "fields": [
                    {
                      "name": "hello",
                      "description": null,
                      "args": [],
                      "type": { "kind": "SCALAR", "name": "String", "ofType": null },
                      "isDeprecated": false,
                      "deprecationReason": null
                    }
                  ],
                  "inputFields": null,
                  "interfaces": [],
                  "enumValues": null,
                  "possibleTypes": null
                },
                {
                  "kind": "SCALAR",
                  "name": "String",
                  "description": null,
                  "fields": null,
                  "inputFields": null,
                  "interfaces": null,
                  "enumValues": null,
                  "possibleTypes": null
                }
              ],
              "directives": []
            }
          }
        }
        """
        return json.data(using: .utf8)!
    }

    private func cleanup() {
        SchemaStore.deleteCachedSchema(for: testEndpoint)
    }

    @Test("Cache round-trip: save and load")
    func cacheRoundTrip() {
        defer { cleanup() }
        let data = sampleIntrospectionJSON

        SchemaStore.cacheSchema(data, for: testEndpoint)
        let loaded = SchemaStore.loadCachedSchema(for: testEndpoint)

        #expect(loaded != nil)
        #expect(loaded == data)
    }

    @Test("Cache miss returns nil")
    func cacheMiss() {
        let result = SchemaStore.loadCachedSchema(for: "https://nonexistent.example.com/graphql")
        #expect(result == nil)
    }

    @Test("Corrupted cache file handled gracefully")
    func corruptedCache() {
        defer { cleanup() }

        // Write invalid data
        SchemaStore.cacheSchema(Data("not valid json".utf8), for: testEndpoint)
        let loaded = SchemaStore.loadCachedSchema(for: testEndpoint)

        // loadCachedSchema returns raw data — corruption is detected at decode time
        #expect(loaded != nil)

        // Verify the decode fails gracefully
        let decoded = try? JSONDecoder().decode(IntrospectionResponse.self, from: loaded!)
        #expect(decoded == nil)

        // Delete and verify miss
        SchemaStore.deleteCachedSchema(for: testEndpoint)
        #expect(SchemaStore.loadCachedSchema(for: testEndpoint) == nil)
    }

    @Test("URL normalization produces consistent cache filenames")
    func consistentHashes() {
        let url1 = SchemaStore.normalizeEndpoint("HTTPS://API.Example.COM/graphql")
        let url2 = SchemaStore.normalizeEndpoint("https://api.example.com/graphql")
        let url3 = SchemaStore.normalizeEndpoint("https://api.example.com/graphql/")

        let hash1 = SchemaStore.cacheFilename(for: url1)
        let hash2 = SchemaStore.cacheFilename(for: url2)
        let hash3 = SchemaStore.cacheFilename(for: url3)

        #expect(hash1 == hash2)
        #expect(hash2 == hash3)
    }

    @Test("Different endpoints produce different cache filenames")
    func differentHashes() {
        let hash1 = SchemaStore.cacheFilename(for: "https://api.example.com/graphql")
        let hash2 = SchemaStore.cacheFilename(for: "https://api.other.com/graphql")
        #expect(hash1 != hash2)
    }

    @Test("Cache filename is a valid SHA256 hex string")
    func cacheFilenameFormat() {
        let filename = SchemaStore.cacheFilename(for: testEndpoint)
        #expect(filename.hasSuffix(".json"))
        let hex = String(filename.dropLast(5)) // remove .json
        #expect(hex.count == 64) // SHA256 = 32 bytes = 64 hex chars
        #expect(hex.allSatisfy { $0.isHexDigit })
    }
}
