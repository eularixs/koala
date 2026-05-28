import Testing
import Foundation
import GRDB
@testable import koala

// MARK: - KoalaDatabaseTests
//
// Uses an in-memory DatabaseQueue so tests are isolated and fast.

@Suite("KoalaDatabase")
struct KoalaDatabaseTests {

    // MARK: - Helper: in-memory DB

    private func makeDB() throws -> KoalaDatabase {
        return try KoalaDatabase(inMemory: true)
    }

    // MARK: - Migration

    @Test("schema creates history_entry table")
    func schemaCreatesHistoryTable() throws {
        let db = try makeDB()
        let exists = try db.dbQueue.read { conn in
            try conn.tableExists("history_entry")
        }
        #expect(exists == true)
    }

    @Test("schema creates recorded_session table")
    func schemaCreatesRecordedSessionTable() throws {
        let db = try makeDB()
        let exists = try db.dbQueue.read { conn in
            try conn.tableExists("recorded_session")
        }
        #expect(exists == true)
    }

    @Test("schema creates recorded_request table")
    func schemaCreatesRecordedRequestTable() throws {
        let db = try makeDB()
        let exists = try db.dbQueue.read { conn in
            try conn.tableExists("recorded_request")
        }
        #expect(exists == true)
    }

    // MARK: - HistoryRepository

    @Test("append then recent returns entry")
    func historyAppendAndRecent() async throws {
        let db = try makeDB()
        let repo = HistoryRepository(db: db)
        let projectId = UUID()
        let entry = makeHistoryEntry(projectId: projectId)

        try await repo.append(entry: entry)
        let rows = try await repo.recent(projectId: projectId, limit: 10)

        #expect(rows.count == 1)
        #expect(rows.first?.id == entry.id.uuidString)
        #expect(rows.first?.method == entry.requestSnapshot.method.rawValue)
    }

    @Test("search filters by URL substring")
    func historySearchFiltersURL() async throws {
        let db = try makeDB()
        let repo = HistoryRepository(db: db)
        let projectId = UUID()

        let e1 = makeHistoryEntry(projectId: projectId, url: "https://api.example.com/users")
        let e2 = makeHistoryEntry(projectId: projectId, url: "https://api.example.com/posts")
        try await repo.append(entry: e1)
        try await repo.append(entry: e2)

        let results = try await repo.search(projectId: projectId, query: "users")
        #expect(results.count == 1)
        #expect(results.first?.url.contains("users") == true)
    }

    @Test("prune removes old entries")
    func historyPrune() async throws {
        let db = try makeDB()
        let repo = HistoryRepository(db: db)
        let projectId = UUID()

        let old = makeHistoryEntry(
            projectId: projectId,
            sentAt: Date().addingTimeInterval(-10 * 86400)  // 10 days ago
        )
        let recent = makeHistoryEntry(projectId: projectId)  // now
        try await repo.append(entry: old)
        try await repo.append(entry: recent)

        try await repo.prune(projectId: projectId, olderThan: Date().addingTimeInterval(-5 * 86400))
        let rows = try await repo.recent(projectId: projectId, limit: 100)
        #expect(rows.count == 1)
        #expect(rows.first?.id == recent.id.uuidString)
    }

    @Test("purge clears all entries for project")
    func historyPurge() async throws {
        let db = try makeDB()
        let repo = HistoryRepository(db: db)
        let projectId = UUID()

        for _ in 0..<5 {
            try await repo.append(entry: makeHistoryEntry(projectId: projectId))
        }
        try await repo.purge(projectId: projectId)
        let rows = try await repo.recent(projectId: projectId, limit: 100)
        #expect(rows.isEmpty)
    }

    @Test("delete removes single entry")
    func historyDeleteSingle() async throws {
        let db = try makeDB()
        let repo = HistoryRepository(db: db)
        let projectId = UUID()

        let e1 = makeHistoryEntry(projectId: projectId)
        let e2 = makeHistoryEntry(projectId: projectId)
        try await repo.append(entry: e1)
        try await repo.append(entry: e2)

        try await repo.delete(id: e1.id)
        let rows = try await repo.recent(projectId: projectId, limit: 100)
        #expect(rows.count == 1)
        #expect(rows.first?.id == e2.id.uuidString)
    }

    // MARK: - RecordingRepository

    @Test("start then end session")
    func recordingSessionLifecycle() async throws {
        let db = try makeDB()
        let repo = RecordingRepository(db: db)

        let session = try await repo.startSession(name: "Test", upstreamUrl: "http://localhost")
        #expect(session.endedAt == nil)

        try await repo.endSession(id: session.id)
        let sessions = try await repo.allSessions()
        let updated = sessions.first(where: { $0.id == session.id })
        #expect(updated?.endedAt != nil)
    }

    @Test("append request then fetch by session")
    func recordingAppendRequest() async throws {
        let db = try makeDB()
        let repo = RecordingRepository(db: db)

        let session = try await repo.startSession(name: "Test", upstreamUrl: nil)
        let request = RecordedRequest(
            method: "POST",
            url: "https://api.example.com/data",
            headers: ["Content-Type": "application/json"],
            requestBody: "{\"foo\":\"bar\"}".data(using: .utf8),
            responseStatus: 201,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{}".data(using: .utf8),
            durationMs: 42,
            host: "api.example.com"
        )
        try await repo.append(request: request, sessionId: session.id)

        let requests = try await repo.requests(in: session.id)
        #expect(requests.count == 1)
        #expect(requests.first?.method == "POST")
        #expect(requests.first?.responseStatus == 201)
    }

    @Test("delete session cascades to requests")
    func recordingDeleteCascades() async throws {
        let db = try makeDB()
        let repo = RecordingRepository(db: db)

        let session = try await repo.startSession(name: "Test", upstreamUrl: nil)
        let request = RecordedRequest(
            method: "GET",
            url: "https://api.example.com/",
            headers: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            durationMs: 10,
            host: "api.example.com"
        )
        try await repo.append(request: request, sessionId: session.id)
        try await repo.deleteSession(id: session.id)

        let sessions = try await repo.allSessions()
        #expect(sessions.isEmpty)
        let requests = try await repo.requests(in: session.id)
        #expect(requests.isEmpty)
    }

    // MARK: - Helpers

    private func makeHistoryEntry(
        projectId: UUID = UUID(),
        url: String = "https://api.example.com/test",
        sentAt: Date = Date()
    ) -> HistoryEntry {
        let req = KoalaRequest(
            name: "Test",
            method: .standard(.get),
            url: url
        )
        return HistoryEntry(
            projectId: projectId,
            requestSnapshot: req,
            responseSnapshot: KoalaResponse(
                statusCode: 200,
                statusText: "OK",
                headers: [:],
                body: Data(),
                durationMs: 10,
                sizeBytes: 0,
                timeline: .zero
            ),
            sentAt: sentAt
        )
    }
}
