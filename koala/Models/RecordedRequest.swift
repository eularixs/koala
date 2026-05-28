import Foundation

// MARK: - RecordedRequest
//
// A single HTTP exchange captured by RecordingProxyService.
// Stored in-memory plus persisted to disk (capped to 1000 entries).
//
// MVP LIMITATION: HTTP only. HTTPS interception requires a CA cert dance
// (generate root CA → install in keychain → intercept TLS via cert pinning).
// That work is deferred to a follow-up iteration; see CACertificateManager.
struct RecordedRequest: Identifiable, Codable, Hashable {
    var id: UUID
    var capturedAt: Date
    var method: String
    /// Full URL including scheme/host/path/query.
    var url: String
    var headers: [String: String]
    var requestBody: Data?
    var responseStatus: Int
    var responseHeaders: [String: String]
    var responseBody: Data?
    var durationMs: Int
    /// Host extracted from URL — used to group rows in the UI.
    var host: String

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        method: String = "GET",
        url: String = "",
        headers: [String: String] = [:],
        requestBody: Data? = nil,
        responseStatus: Int = 0,
        responseHeaders: [String: String] = [:],
        responseBody: Data? = nil,
        durationMs: Int = 0,
        host: String = ""
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.method = method
        self.url = url
        self.headers = headers
        self.requestBody = requestBody
        self.responseStatus = responseStatus
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.durationMs = durationMs
        self.host = host
    }

    /// Path component of the URL (for compact display in row).
    var path: String {
        guard let comps = URLComponents(string: url) else { return url }
        let p = comps.path.isEmpty ? "/" : comps.path
        if let q = comps.query, !q.isEmpty { return "\(p)?\(q)" }
        return p
    }

    /// Request body decoded as UTF-8 string (best effort).
    var requestBodyString: String? {
        guard let d = requestBody, !d.isEmpty else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Response body decoded as UTF-8 string (best effort).
    var responseBodyString: String? {
        guard let d = responseBody, !d.isEmpty else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
