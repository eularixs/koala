import Foundation

// NOTE: Using plain Codable JSON files in Application Support. SwiftData migration deferred.

final class PersistenceService {
    private let baseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Koala")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: Collections

    func loadCollections() throws -> [KoalaCollection] {
        try loadArray(from: "collections.json")
    }

    func saveCollections(_ collections: [KoalaCollection]) throws {
        try save(collections, to: "collections.json")
    }

    // MARK: Environments

    func loadEnvironments() throws -> [KoalaEnvironment] {
        try loadArray(from: "environments.json")
    }

    func saveEnvironments(_ environments: [KoalaEnvironment]) throws {
        try save(environments, to: "environments.json")
    }

    // MARK: Globals

    func loadGlobals() throws -> [KeyValuePair] {
        try loadArray(from: "globals.json")
    }

    func saveGlobals(_ items: [KeyValuePair]) throws {
        try save(items, to: "globals.json")
    }

    // MARK: Helpers

    private func loadArray<T: Decodable>(from filename: String) throws -> [T] {
        let url = baseURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([T].self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to filename: String) throws {
        let url = baseURL.appendingPathComponent(filename)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomicWrite)
    }
}
