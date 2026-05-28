import Foundation
import GRDB

// MARK: - RecordedSessionRow

struct RecordedSessionRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recorded_session"

    var id: String
    var name: String
    var upstreamUrl: String?
    var startedAt: Int
    var endedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case upstreamUrl = "upstream_url"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

// MARK: - RecordedRequestRow

struct RecordedRequestRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recorded_request"

    var id: String
    var sessionId: String
    var method: String
    var url: String
    var headersJson: String?
    var requestBody: Data?
    var responseStatus: Int?
    var responseHeadersJson: String?
    var responseBody: Data?
    var responseBodyPath: String?
    var capturedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case method, url
        case headersJson = "headers_json"
        case requestBody = "request_body"
        case responseStatus = "response_status"
        case responseHeadersJson = "response_headers_json"
        case responseBody = "response_body"
        case responseBodyPath = "response_body_path"
        case capturedAt = "captured_at"
    }
}

// MARK: - RecordingRepository

final class RecordingRepository: Sendable {

    private let db: KoalaDatabase

    init(db: KoalaDatabase = .shared) {
        self.db = db
    }

    // MARK: Session

    func startSession(name: String, upstreamUrl: String?) async throws -> RecordedSessionRow {
        let row = RecordedSessionRow(
            id: UUID().uuidString,
            name: name,
            upstreamUrl: upstreamUrl,
            startedAt: Int(Date().timeIntervalSince1970),
            endedAt: nil
        )
        try await db.dbQueue.write { dbConn in
            try row.insert(dbConn)
        }
        return row
    }

    func endSession(id: String) async throws {
        let endedAt = Int(Date().timeIntervalSince1970)
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE recorded_session SET ended_at = ? WHERE id = ?",
                arguments: [endedAt, id]
            )
        }
    }

    func allSessions() async throws -> [RecordedSessionRow] {
        try await db.dbQueue.read { dbConn in
            try RecordedSessionRow
                .order(Column("started_at").desc)
                .fetchAll(dbConn)
        }
    }

    func deleteSession(id: String) async throws {
        try await db.dbQueue.write { dbConn in
            // Fetch blobs to clean up before cascade delete.
            let requests = try RecordedRequestRow
                .filter(Column("session_id") == id)
                .fetchAll(dbConn)
            for req in requests {
                KoalaDatabase.deleteBlob(at: req.responseBodyPath)
            }
            try RecordedSessionRow.deleteOne(dbConn, key: id)
        }
    }

    // MARK: Requests

    func append(request: RecordedRequest, sessionId: String) async throws {
        let responseBody = request.responseBody ?? Data()
        let (inlineBody, bodyPath) = try KoalaDatabase.storeBody(
            responseBody,
            id: request.id.uuidString + "-resp"
        )
        let headersJson = encodeJson(request.headers)
        let respHeadersJson = encodeJson(request.responseHeaders)

        let row = RecordedRequestRow(
            id: request.id.uuidString,
            sessionId: sessionId,
            method: request.method,
            url: request.url,
            headersJson: headersJson,
            requestBody: request.requestBody,
            responseStatus: request.responseStatus,
            responseHeadersJson: respHeadersJson,
            responseBody: inlineBody,
            responseBodyPath: bodyPath,
            capturedAt: Int(request.capturedAt.timeIntervalSince1970)
        )
        try await db.dbQueue.write { dbConn in
            try row.insert(dbConn, onConflict: .replace)
        }
    }

    func requests(in sessionId: String) async throws -> [RecordedRequestRow] {
        try await db.dbQueue.read { dbConn in
            try RecordedRequestRow
                .filter(Column("session_id") == sessionId)
                .order(Column("captured_at"))
                .fetchAll(dbConn)
        }
    }

    // MARK: Private

    private func encodeJson(_ dict: [String: String]) -> String? {
        guard !dict.isEmpty,
              let data = try? JSONEncoder().encode(dict),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
