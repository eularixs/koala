import Foundation
import Observation

@MainActor
@Observable
final class HistoryService {
    private static let maxEntries = 500
    private static let filename = "history.json"

    var entries: [HistoryEntry] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Koala")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(HistoryService.filename)
    }()

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        #if DEBUG
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        #else
        e.outputFormatting = .sortedKeys
        #endif
        return e
    }

    private let decoder = JSONDecoder()

    func record(request: KoalaRequest, response: KoalaResponse?) {
        let entry = HistoryEntry(requestSnapshot: request, responseSnapshot: response)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        Task { await persistAsync() }
    }

    func clear() {
        entries = []
        Task { await persistAsync() }
    }

    func remove(_ id: UUID) {
        entries.removeAll(where: { $0.id == id })
        Task { await persistAsync() }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? decoder.decode([HistoryEntry].self, from: data) else { return }
        entries = loaded
    }

    private func persistAsync() async {
        let snapshot = entries
        let url = fileURL
        let enc = encoder
        await Task.detached(priority: .background) {
            guard let data = try? enc.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomicWrite)
        }.value
    }
}
