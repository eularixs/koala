import Foundation

// MARK: - Response Timeline

struct ResponseTimeline: Codable, Hashable {
    var dnsMs: Int
    var connectMs: Int
    var tlsMs: Int
    var ttfbMs: Int
    var downloadMs: Int

    var totalMs: Int {
        dnsMs + connectMs + tlsMs + ttfbMs + downloadMs
    }

    static var zero: ResponseTimeline {
        ResponseTimeline(dnsMs: 0, connectMs: 0, tlsMs: 0, ttfbMs: 0, downloadMs: 0)
    }
}

// MARK: - KoalaResponse

struct KoalaResponse: Codable, Hashable {
    var statusCode: Int
    var statusText: String
    var headers: [String: String]
    var body: Data
    var durationMs: Int
    var sizeBytes: Int
    var timeline: ResponseTimeline
    /// Test assertions produced by the post-response script.
    var testResults: [TestResult] = []
    /// `console.log(...)` output captured during script execution.
    var consoleLogs: [String] = []

    var isSuccess: Bool { (200..<300).contains(statusCode) }
    var isClientError: Bool { (400..<500).contains(statusCode) }
    var isServerError: Bool { (500..<600).contains(statusCode) }

    static var empty: KoalaResponse {
        KoalaResponse(
            statusCode: 0,
            statusText: "",
            headers: [:],
            body: Data(),
            durationMs: 0,
            sizeBytes: 0,
            timeline: .zero
        )
    }

    // MARK: Backwards-compatible decode (testResults / consoleLogs default to empty)
    enum CodingKeys: String, CodingKey {
        case statusCode, statusText, headers, body, durationMs, sizeBytes, timeline
        case testResults, consoleLogs
    }

    init(
        statusCode: Int,
        statusText: String,
        headers: [String: String],
        body: Data,
        durationMs: Int,
        sizeBytes: Int,
        timeline: ResponseTimeline,
        testResults: [TestResult] = [],
        consoleLogs: [String] = []
    ) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.timeline = timeline
        self.testResults = testResults
        self.consoleLogs = consoleLogs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try c.decode(Int.self, forKey: .statusCode)
        statusText = try c.decode(String.self, forKey: .statusText)
        headers = try c.decode([String: String].self, forKey: .headers)
        body = try c.decode(Data.self, forKey: .body)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        sizeBytes = try c.decode(Int.self, forKey: .sizeBytes)
        timeline = try c.decode(ResponseTimeline.self, forKey: .timeline)
        testResults = (try? c.decodeIfPresent([TestResult].self, forKey: .testResults)) ?? []
        consoleLogs = (try? c.decodeIfPresent([String].self, forKey: .consoleLogs)) ?? []
    }
}

// MARK: - KoalaRequest

struct KoalaRequest: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var method: HTTPMethodValue
    var url: String
    var queryParams: [KeyValuePair]
    var headers: [KeyValuePair]
    var auth: AuthConfig
    var body: RequestBody
    var preRequestScript: String?
    var testScript: String?
    /// Whether this request is served from the mock endpoint instead of the live URL.
    var isMock: Bool
    /// Free-form markdown notes documenting the request. Optional for backwards-compat.
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "New Request",
        method: HTTPMethodValue = .standard(.get),
        url: String = "",
        queryParams: [KeyValuePair] = [],
        headers: [KeyValuePair] = [],
        auth: AuthConfig = .none,
        body: RequestBody = .none,
        preRequestScript: String? = nil,
        testScript: String? = nil,
        isMock: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.url = url
        self.queryParams = queryParams
        self.headers = headers
        self.auth = auth
        self.body = body
        self.preRequestScript = preRequestScript
        self.testScript = testScript
        self.isMock = isMock
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Backwards-compatible decode — isMock defaults to false for older data
    enum CodingKeys: String, CodingKey {
        case id, name, method, url, queryParams, headers, auth, body
        case preRequestScript, testScript, isMock, notes, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        method = try c.decode(HTTPMethodValue.self, forKey: .method)
        url = try c.decode(String.self, forKey: .url)
        queryParams = (try? c.decode([KeyValuePair].self, forKey: .queryParams)) ?? []
        headers = (try? c.decode([KeyValuePair].self, forKey: .headers)) ?? []
        auth = (try? c.decode(AuthConfig.self, forKey: .auth)) ?? .none
        body = (try? c.decode(RequestBody.self, forKey: .body)) ?? .none
        preRequestScript = try? c.decodeIfPresent(String.self, forKey: .preRequestScript)
        testScript = try? c.decodeIfPresent(String.self, forKey: .testScript)
        isMock = (try? c.decodeIfPresent(Bool.self, forKey: .isMock)) ?? false
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    static var empty: KoalaRequest { KoalaRequest() }
}
