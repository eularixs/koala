import Foundation
import Observation

@MainActor
@Observable
final class HistoryService {
    private static let maxEntries = 100

    /// In-memory cache for UI binding — loaded from SQLite on project switch.
    var entries: [HistoryEntry] = []
    private var activeProjectId: UUID? = nil

    private let repo = HistoryRepository()

    // MARK: - Per-project history

    func loadForProject(_ id: UUID?) {
        activeProjectId = id
        guard let id else {
            entries = []
            return
        }
        Task {
            await loadFromDB(projectId: id)
        }
    }

    func record(request: KoalaRequest, response: KoalaResponse?, projectId: UUID) {
        let entry = HistoryEntry(
            projectId: projectId,
            requestSnapshot: request,
            responseSnapshot: response
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        Task {
            try? await repo.append(entry: entry)
        }
    }

    func clear(projectId: UUID) {
        entries = []
        Task {
            try? await repo.purge(projectId: projectId)
        }
    }

    func remove(_ id: UUID, projectId: UUID) {
        entries.removeAll(where: { $0.id == id })
        Task {
            try? await repo.delete(id: id)
        }
    }

    /// Convenience: clear history for the currently active project.
    func clear() {
        guard let id = activeProjectId else { entries = []; return }
        clear(projectId: id)
    }

    /// Convenience: remove a history entry for the currently active project.
    func remove(_ id: UUID) {
        guard let pid = activeProjectId else {
            entries.removeAll(where: { $0.id == id })
            return
        }
        remove(id, projectId: pid)
    }

    /// Legacy no-arg load — no-op after migration; use loadForProject instead.
    func load() {}

    // MARK: - Private

    private func loadFromDB(projectId: UUID) async {
        let rows = (try? await repo.recent(projectId: projectId, limit: Self.maxEntries)) ?? []
        let loaded = rows.compactMap { HistoryEntry(from: $0) }
        await MainActor.run { self.entries = loaded }
    }
}

// MARK: - HistoryEntry init from HistoryRow

extension HistoryEntry {
    init?(from row: HistoryRow) {
        guard let projectId = UUID(uuidString: row.projectId) else { return nil }
        let method = HTTPMethodValue.from(string: row.method)
        let request = KoalaRequest(
            name: row.url,
            method: method,
            url: row.url
        )
        var response: KoalaResponse? = nil
        if let statusCode = row.statusCode {
            let bodyData = KoalaDatabase.loadBody(inline: row.responseBody, path: row.responseBodyPath) ?? Data()
            let headers = decodeHeadersJson(row.responseHeadersJson)
            response = KoalaResponse(
                statusCode: statusCode,
                statusText: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                headers: headers,
                body: bodyData,
                durationMs: row.durationMs ?? 0,
                sizeBytes: bodyData.count,
                timeline: .zero
            )
        }
        self.init(
            id: UUID(uuidString: row.id) ?? UUID(),
            projectId: projectId,
            requestSnapshot: request,
            responseSnapshot: response,
            sentAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt))
        )
    }
}

private func decodeHeadersJson(_ json: String?) -> [String: String] {
    guard let json, let data = json.data(using: .utf8) else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
}
