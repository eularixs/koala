import Foundation
import Observation

@MainActor
@Observable
final class HistoryService {
    private static let maxEntries = 500

    var entries: [HistoryEntry] = []
    private var activeProjectId: UUID? = nil

    private let persistence = PersistenceService()

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        #if DEBUG
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        #else
        e.outputFormatting = .sortedKeys
        #endif
        return e
    }

    // MARK: - Per-project history

    func loadForProject(_ id: UUID?) {
        activeProjectId = id
        guard let id else {
            entries = []
            return
        }
        entries = (try? persistence.loadHistory(forProject: id)) ?? []
    }

    func record(request: KoalaRequest, response: KoalaResponse?, projectId: UUID) {
        let entry = HistoryEntry(projectId: projectId, requestSnapshot: request, responseSnapshot: response)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        let snapshot = entries
        let pid = projectId
        let ps = persistence
        let enc = encoder
        Task {
            await persistAsync(snapshot, projectId: pid, persistence: ps, encoder: enc)
        }
    }

    func clear(projectId: UUID) {
        entries = []
        let ps = persistence
        let enc = encoder
        Task {
            await persistAsync([], projectId: projectId, persistence: ps, encoder: enc)
        }
    }

    func remove(_ id: UUID, projectId: UUID) {
        entries.removeAll(where: { $0.id == id })
        let snapshot = entries
        let ps = persistence
        let enc = encoder
        Task {
            await persistAsync(snapshot, projectId: projectId, persistence: ps, encoder: enc)
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

    private func persistAsync(
        _ snapshot: [HistoryEntry],
        projectId: UUID,
        persistence: PersistenceService,
        encoder: JSONEncoder
    ) async {
        await Task.detached(priority: .background) {
            try? persistence.saveHistory(snapshot, forProject: projectId)
        }.value
    }
}
