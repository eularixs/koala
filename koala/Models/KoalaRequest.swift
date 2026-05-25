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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static var empty: KoalaRequest { KoalaRequest() }
}
