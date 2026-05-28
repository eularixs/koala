import Foundation

// MARK: - JSONToSQLiteMigrator
//
// One-time data migration: reads existing per-project JSON history files
// and batch-inserts them into SQLite via HistoryRepository.
// On completion sets UserDefaults flag "KoalaSQLiteMigrationDone" = true.
// Original JSON files are renamed to *.migrated.bak (not deleted).

final class JSONToSQLiteMigrator {

    private static let migrationKey = "KoalaSQLiteMigrationDone"

    static var isDone: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    private let historyRepo: HistoryRepository
    private let recordingRepo: RecordingRepository

    init(historyRepo: HistoryRepository = .init(), recordingRepo: RecordingRepository = .init()) {
        self.historyRepo = historyRepo
        self.recordingRepo = recordingRepo
    }

    /// Runs migration if not already done. Safe to call on every launch.
    func migrateIfNeeded() async {
        guard !Self.isDone else { return }
        await migrateHistory()
        await migrateCaptures()
        UserDefaults.standard.set(true, forKey: Self.migrationKey)
    }

    // MARK: - History migration

    private func migrateHistory() async {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let koalaDir = appSupport.appendingPathComponent("Koala")
        let projectsDir = koalaDir.appendingPathComponent("projects")

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for projectDir in projectDirs {
            let historyFile = projectDir.appendingPathComponent("history.json")
            guard FileManager.default.fileExists(atPath: historyFile.path) else { continue }
            await migrateHistoryFile(historyFile)
        }
    }

    private func migrateHistoryFile(_ url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([HistoryEntry].self, from: data) else { return }

        for entry in entries {
            try? await historyRepo.append(entry: entry)
        }

        let bakURL = url.deletingLastPathComponent()
            .appendingPathComponent("history.json.migrated.bak")
        try? FileManager.default.moveItem(at: url, to: bakURL)
    }

    // MARK: - Captures migration

    private func migrateCaptures() async {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let capturesFile = appSupport
            .appendingPathComponent("Koala")
            .appendingPathComponent("recordings")
            .appendingPathComponent("captures.json")

        guard FileManager.default.fileExists(atPath: capturesFile.path) else { return }
        guard let data = try? Data(contentsOf: capturesFile) else { return }
        let decoder = JSONDecoder()
        guard let captures = try? decoder.decode([RecordedRequest].self, from: data),
              !captures.isEmpty else { return }

        guard let session = try? await recordingRepo.startSession(
            name: "Migrated Captures",
            upstreamUrl: nil
        ) else { return }

        for capture in captures {
            try? await recordingRepo.append(request: capture, sessionId: session.id)
        }
        try? await recordingRepo.endSession(id: session.id)

        let bakURL = capturesFile.deletingLastPathComponent()
            .appendingPathComponent("captures.json.migrated.bak")
        try? FileManager.default.moveItem(at: capturesFile, to: bakURL)
    }
}
