import Foundation

/// File-backed history store for `AutomationRun`. Append-only with rotation:
/// the newest `maxEntries` runs per schedule are kept on disk.
///
/// Layout:
/// `~/Library/Application Support/Koala/projects/{pid}/automation/runs-{scheduleId}.json`
final class AutomationRunStore {
    static let maxEntries = 200

    private let baseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Koala")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Public API

    func load(forProject projectId: UUID, scheduleId: UUID) -> [AutomationRun] {
        let url = runsURL(projectId: projectId, scheduleId: scheduleId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let runs = try? decoder.decode([AutomationRun].self, from: data) else {
            return []
        }
        return runs
    }

    /// Appends a run and truncates oldest entries beyond `maxEntries`.
    func append(_ run: AutomationRun, forProject projectId: UUID) {
        var runs = load(forProject: projectId, scheduleId: run.scheduleId)
        runs.append(run)
        // Keep newest N — sort by startedAt desc, then trim.
        runs.sort { $0.startedAt > $1.startedAt }
        if runs.count > Self.maxEntries {
            runs = Array(runs.prefix(Self.maxEntries))
        }
        save(runs, forProject: projectId, scheduleId: run.scheduleId)
    }

    func delete(scheduleId: UUID, forProject projectId: UUID) {
        let url = runsURL(projectId: projectId, scheduleId: scheduleId)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Internals

    private func save(_ runs: [AutomationRun], forProject projectId: UUID, scheduleId: UUID) {
        let dir = automationDir(projectId: projectId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = runsURL(projectId: projectId, scheduleId: scheduleId)
        if let data = try? encoder.encode(runs) {
            try? data.write(to: url, options: .atomicWrite)
        }
    }

    private func automationDir(projectId: UUID) -> URL {
        baseURL
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("automation")
    }

    private func runsURL(projectId: UUID, scheduleId: UUID) -> URL {
        automationDir(projectId: projectId)
            .appendingPathComponent("runs-\(scheduleId.uuidString).json")
    }
}
