import Foundation
import GRDB

// MARK: - HistoryRow
//
// GRDB-mapped row for history_entry table.

struct HistoryRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "history_entry"

    var id: String
    var projectId: String
    var requestId: String?
    var method: String
    var url: String
    var statusCode: Int?
    var durationMs: Int?
    var requestHeadersJson: String?
    var requestBody: Data?
    var responseHeadersJson: String?
    var responseBody: Data?
    var responseBodyPath: String?
    var createdAt: Int  // unix epoch seconds

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case requestId = "request_id"
        case method
        case url
        case statusCode = "status_code"
        case durationMs = "duration_ms"
        case requestHeadersJson = "request_headers_json"
        case requestBody = "request_body"
        case responseHeadersJson = "response_headers_json"
        case responseBody = "response_body"
        case responseBodyPath = "response_body_path"
        case createdAt = "created_at"
    }
}

// MARK: - HistoryRepository

final class HistoryRepository: Sendable {

    private let db: KoalaDatabase

    init(db: KoalaDatabase = .shared) {
        self.db = db
    }

    /// Inserts a new history entry derived from a HistoryEntry model.
    func append(entry: HistoryEntry) async throws {
        let responseBody = entry.responseSnapshot?.body ?? Data()
        let (inlineBody, bodyPath) = try KoalaDatabase.storeBody(
            responseBody,
            id: entry.id.uuidString + "-resp"
        )
        let reqHeaders = entry.requestSnapshot.headers
            .filter { $0.isEnabled }
            .reduce(into: [String: String]()) { $0[$1.key] = $1.value }
        let reqHeadersJson = encodeHeadersJson(reqHeaders)
        let respHeaders: [String: String] = entry.responseSnapshot?.headers ?? [:]
        let respHeadersJson = encodeHeadersJson(respHeaders)

        let row = HistoryRow(
            id: entry.id.uuidString,
            projectId: entry.projectId.uuidString,
            requestId: nil,
            method: entry.requestSnapshot.method.rawValue,
            url: entry.requestSnapshot.url,
            statusCode: entry.responseSnapshot?.statusCode,
            durationMs: entry.responseSnapshot?.durationMs,
            requestHeadersJson: reqHeadersJson,
            requestBody: entry.requestSnapshot.bodyData,
            responseHeadersJson: respHeadersJson,
            responseBody: inlineBody,
            responseBodyPath: bodyPath,
            createdAt: Int(entry.sentAt.timeIntervalSince1970)
        )
        try await db.dbQueue.write { dbConn in
            try row.insert(dbConn, onConflict: .replace)
        }
    }

    /// Returns most recent N entries for a project.
    func recent(projectId: UUID, limit: Int = 100) async throws -> [HistoryRow] {
        try await db.dbQueue.read { dbConn in
            try HistoryRow
                .filter(Column("project_id") == projectId.uuidString)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(dbConn)
        }
    }

    /// Full-text search over method + URL for a project.
    func search(projectId: UUID, query: String) async throws -> [HistoryRow] {
        let pattern = "%\(query)%"
        return try await db.dbQueue.read { dbConn in
            try HistoryRow
                .filter(Column("project_id") == projectId.uuidString)
                .filter(Column("url").like(pattern) || Column("method").like(pattern))
                .order(Column("created_at").desc)
                .fetchAll(dbConn)
        }
    }

    /// Deletes entries older than a given date for a project.
    func prune(projectId: UUID, olderThan date: Date) async throws {
        let cutoff = Int(date.timeIntervalSince1970)
        try await db.dbQueue.write { dbConn in
            let rows = try HistoryRow
                .filter(Column("project_id") == projectId.uuidString)
                .filter(Column("created_at") < cutoff)
                .fetchAll(dbConn)
            for row in rows {
                KoalaDatabase.deleteBlob(at: row.responseBodyPath)
            }
            try HistoryRow
                .filter(Column("project_id") == projectId.uuidString)
                .filter(Column("created_at") < cutoff)
                .deleteAll(dbConn)
        }
    }

    /// Deletes all history entries for a project.
    func purge(projectId: UUID) async throws {
        try await db.dbQueue.write { dbConn in
            let rows = try HistoryRow
                .filter(Column("project_id") == projectId.uuidString)
                .fetchAll(dbConn)
            for row in rows {
                KoalaDatabase.deleteBlob(at: row.responseBodyPath)
            }
            try HistoryRow
                .filter(Column("project_id") == projectId.uuidString)
                .deleteAll(dbConn)
        }
    }

    /// Deletes a single entry by ID.
    func delete(id: UUID) async throws {
        try await db.dbQueue.write { dbConn in
            if let row = try HistoryRow.fetchOne(dbConn, key: id.uuidString) {
                KoalaDatabase.deleteBlob(at: row.responseBodyPath)
            }
            try HistoryRow.deleteOne(dbConn, key: id.uuidString)
        }
    }

    // MARK: Private

    private func encodeHeadersJson(_ headers: [String: String]) -> String? {
        guard !headers.isEmpty,
              let data = try? JSONEncoder().encode(headers),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}

// MARK: - HistoryEntry body helpers

private extension KoalaRequest {
    var bodyData: Data? {
        switch body {
        case .raw(let text, _): return text.data(using: .utf8)
        case .json(let text): return text.data(using: .utf8)
        case .graphql(let query, _): return query.data(using: .utf8)
        case .formURLEncoded, .multipart, .binary, .none: return nil
        }
    }
}
