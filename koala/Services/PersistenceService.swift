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

    // MARK: - Projects Manifest

    func loadProjects() throws -> ProjectsManifest {
        migrateLegacyIfNeeded()
        let url = baseURL.appendingPathComponent("projects.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ProjectsManifest() }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ProjectsManifest.self, from: data)
    }

    func saveProjects(_ manifest: ProjectsManifest) throws {
        try save(manifest, to: baseURL.appendingPathComponent("projects.json"))
    }

    // MARK: - Per-Project Collections

    func loadCollections(forProject id: UUID) throws -> [KoalaCollection] {
        try loadArray(from: projectURL(id, "collections.json"))
    }

    func saveCollections(_ collections: [KoalaCollection], forProject id: UUID) throws {
        try ensureProjectDir(id)
        try save(collections, to: projectURL(id, "collections.json"))
    }

    // MARK: - Per-Project Environments

    func loadEnvironments(forProject id: UUID) throws -> [KoalaEnvironment] {
        try loadArray(from: projectURL(id, "environments.json"))
    }

    func saveEnvironments(_ environments: [KoalaEnvironment], forProject id: UUID) throws {
        try ensureProjectDir(id)
        try save(environments, to: projectURL(id, "environments.json"))
    }

    // MARK: - Per-Project Globals

    func loadGlobals(forProject id: UUID) throws -> [KeyValuePair] {
        try loadArray(from: projectURL(id, "globals.json"))
    }

    func saveGlobals(_ items: [KeyValuePair], forProject id: UUID) throws {
        try ensureProjectDir(id)
        try save(items, to: projectURL(id, "globals.json"))
    }

    // MARK: - Per-Project History

    func loadHistory(forProject id: UUID) throws -> [HistoryEntry] {
        try loadArray(from: projectURL(id, "history.json"))
    }

    func saveHistory(_ entries: [HistoryEntry], forProject id: UUID) throws {
        try ensureProjectDir(id)
        try save(entries, to: projectURL(id, "history.json"))
    }

    // MARK: - Per-Project Mock Servers

    func loadMockServers(forProject id: UUID) throws -> [MockServer] {
        try loadArray(from: projectURL(id, "mock_servers.json"))
    }

    func saveMockServers(_ servers: [MockServer], forProject id: UUID) throws {
        try ensureProjectDir(id)
        try save(servers, to: projectURL(id, "mock_servers.json"))
    }

    // MARK: - Delete Project Data

    func deleteProjectData(_ id: UUID) throws {
        let dir = projectDir(id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: - Legacy Migration

    /// One-time migration: if `projects.json` doesn't exist but legacy root-level files do,
    /// create a "Default" project and move the files into `projects/<id>/`.
    func migrateLegacyIfNeeded() {
        let manifestURL = baseURL.appendingPathComponent("projects.json")
        guard !FileManager.default.fileExists(atPath: manifestURL.path) else { return }

        let legacyFiles = ["collections.json", "environments.json", "globals.json", "history.json"]
        let hasLegacy = legacyFiles.contains { name in
            FileManager.default.fileExists(atPath: baseURL.appendingPathComponent(name).path)
        }
        guard hasLegacy else { return }

        let defaultProject = Project(name: "Default", slug: "default")
        try? ensureProjectDir(defaultProject.id)

        for name in legacyFiles {
            let src = baseURL.appendingPathComponent(name)
            let dst = projectURL(defaultProject.id, name)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            try? FileManager.default.moveItem(at: src, to: dst)
        }

        let manifest = ProjectsManifest(projects: [defaultProject], activeProjectId: defaultProject.id)
        try? save(manifest, to: manifestURL)
    }

    // MARK: - Helpers

    private func projectDir(_ id: UUID) -> URL {
        baseURL.appendingPathComponent("projects").appendingPathComponent(id.uuidString)
    }

    private func projectURL(_ id: UUID, _ filename: String) -> URL {
        projectDir(id).appendingPathComponent(filename)
    }

    private func ensureProjectDir(_ id: UUID) throws {
        let dir = projectDir(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func loadArray<T: Decodable>(from url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([T].self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomicWrite)
    }
}
