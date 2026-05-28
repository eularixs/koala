import Foundation
import GRDB

// MARK: - KoalaDatabase
//
// Singleton DatabaseQueue backed by SQLite in WAL mode.
// Opened at ~/Library/Application Support/Koala/koala.sqlite.
// All migrations are registered here via GRDB's DatabaseMigrator.

final class KoalaDatabase: Sendable {

    static let shared: KoalaDatabase = {
        let db = try! KoalaDatabase()
        return db
    }()

    let dbQueue: DatabaseQueue

    /// Blob storage root — large bodies are externalized here.
    static let blobsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Koala").appendingPathComponent("blobs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Bodies smaller than or equal to this are stored inline as BLOB.
    static let inlineBodyLimit: Int = 100 * 1024  // 100 KB

    /// Production initializer: opens the on-disk SQLite at ~/Library/Application Support/Koala/koala.sqlite.
    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Koala")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("koala.sqlite").path

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        try migrate()
    }

    /// Test initializer: opens an in-memory SQLite (no file created).
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init() for production; pass inMemory: true for tests.")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbQueue = try DatabaseQueue(configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS history_entry (
                    id TEXT PRIMARY KEY,
                    project_id TEXT NOT NULL,
                    request_id TEXT,
                    method TEXT NOT NULL,
                    url TEXT NOT NULL,
                    status_code INTEGER,
                    duration_ms INTEGER,
                    request_headers_json TEXT,
                    request_body BLOB,
                    response_headers_json TEXT,
                    response_body BLOB,
                    response_body_path TEXT,
                    created_at INTEGER NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_history_project_created
                ON history_entry(project_id, created_at DESC)
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS recorded_session (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    upstream_url TEXT,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER
                )
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS recorded_request (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    method TEXT NOT NULL,
                    url TEXT NOT NULL,
                    headers_json TEXT,
                    request_body BLOB,
                    response_status INTEGER,
                    response_headers_json TEXT,
                    response_body BLOB,
                    response_body_path TEXT,
                    captured_at INTEGER NOT NULL,
                    FOREIGN KEY(session_id) REFERENCES recorded_session(id) ON DELETE CASCADE
                )
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_recorded_session_captured
                ON recorded_request(session_id, captured_at)
                """)
        }
        try migrator.migrate(dbQueue)
    }
}

// MARK: - Blob helpers

extension KoalaDatabase {

    /// Stores body either inline (if <= limit) or in blobs dir. Returns (inlineData, externalPath).
    static func storeBody(_ data: Data, id: String) throws -> (Data?, String?) {
        if data.count <= inlineBodyLimit {
            return (data, nil)
        }
        let path = blobsDirectory.appendingPathComponent("\(id).bin").path
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return (nil, path)
    }

    /// Loads body from inline data or external file path.
    static func loadBody(inline: Data?, path: String?) -> Data? {
        if let inline { return inline }
        guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return data
    }

    /// Deletes external blob file if it exists.
    static func deleteBlob(at path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
