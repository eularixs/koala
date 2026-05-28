import XCTest
import NIO
import NIOHTTP1
@testable import koala

// MARK: - ProxyRoutingNIOIntegrationTest
//
// Re-runs the core routing logic via processHTTPRequest to confirm the NIO path
// preserves existing multi-upstream routing, header-rewriting, and capture behaviour.

final class ProxyRoutingNIOIntegrationTest: XCTestCase {

    private var svc: RecordingProxyService!

    override func setUp() async throws {
        try await super.setUp()
        svc = await MainActor.run { RecordingProxyService() }
    }

    // MARK: Upstream resolution (reverse mode)

    func testResolveUpstream_reverseMode_authPrefix() {
        let rules: [UpstreamRule] = [
            UpstreamRule(pathPrefix: "/__auth", upstream: URL(string: "https://api.auth.example.com")!),
            UpstreamRule(pathPrefix: "/",        upstream: URL(string: "https://example.com")!),
        ]
        let resolved = svc.resolveUpstream(path: "/__auth/sign-in", rules: rules)
        XCTAssertEqual(resolved?.host, "api.auth.example.com")
        XCTAssertEqual(resolved?.path, "/sign-in")
    }

    func testResolveUpstream_reverseMode_catchAll() {
        let rules: [UpstreamRule] = [
            UpstreamRule(pathPrefix: "/__auth", upstream: URL(string: "https://api.auth.example.com")!),
            UpstreamRule(pathPrefix: "/",        upstream: URL(string: "https://example.com")!),
        ]
        let resolved = svc.resolveUpstream(path: "/about", rules: rules)
        XCTAssertEqual(resolved?.host, "example.com")
        XCTAssertEqual(resolved?.path, "/about")
    }

    // MARK: Header rewriting (nonisolated functions still work post-refactor)

    func testRewriteRequestHeaders_reverseMode_setsHostHeader() {
        let upstream = URL(string: "https://api.example.com")!
        let headers: [(String, String)] = [
            ("Accept", "application/json"),
            ("Content-Length", "0"),   // should be stripped
        ]
        let rewritten = svc.rewriteRequestHeaders(headers, upstream: upstream, mode: .reverse(rules: []))
        let keys = rewritten.map { $0.0.lowercased() }
        XCTAssertTrue(keys.contains("host"))
        XCTAssertFalse(keys.contains("content-length"), "content-length is hop-by-hop and should be stripped")
    }

    func testRewriteRequestHeaders_forwardMode_noHostInjected() {
        let upstream = URL(string: "https://api.example.com")!
        let headers: [(String, String)] = [("Accept", "application/json")]
        let rewritten = svc.rewriteRequestHeaders(headers, upstream: upstream, mode: .forward)
        let keys = rewritten.map { $0.0.lowercased() }
        // Forward mode does not inject Host header
        XCTAssertFalse(keys.contains("host"), "Forward mode must not inject Host header")
    }

    // MARK: Body rewriting

    func testRewriteBody_replacesUpstreamURLs() {
        let rules = [UpstreamRule(pathPrefix: "/", upstream: URL(string: "https://api.example.com")!)]
        let body = """
        {"url":"https://api.example.com/v1/users"}
        """.data(using: .utf8)!

        let result = svc.rewriteBodyMulti(body, contentType: "application/json", rules: rules, localPort: 8080)
        let resultStr = String(data: result, encoding: .utf8) ?? ""
        XCTAssertTrue(resultStr.contains("http://localhost:8080"), "Body must have upstream URL replaced")
        XCTAssertFalse(resultStr.contains("https://api.example.com"), "Original upstream URL must be removed")
    }

    // MARK: Capture filter preserved

    func testCaptureFilter_skipStaticAssets_stillWorks() {
        let filter = CaptureFilter(skipStaticAssets: true, pathGlobs: [])
        XCTAssertFalse(svc.testShouldCapture(path: "/app.js", contentType: "application/javascript", filter: filter))
        XCTAssertTrue(svc.testShouldCapture(path: "/api/users", contentType: "application/json", filter: filter))
    }

    // MARK: processHTTPRequest - ProxyResult structure

    /// Ensures processHTTPRequest returns a valid ProxyResult for a bad-target request (400 path).
    func testProcessHTTPRequest_invalidURL_returns400() async throws {
        await MainActor.run { svc.mode = .forward }

        var head = HTTPRequestHead(
            version: .init(major: 1, minor: 1),
            method: .GET,
            uri: "/relative-path-no-host"
        )
        // No Host header — forces URL resolution to fail

        let result = await MainActor.run { self.svc }.processHTTPRequest(head: head, body: nil, connectHost: nil)
        XCTAssertEqual(result.status, 400)
    }
}
