import XCTest
@testable import koala

// MARK: - ProxyHeaderRewriterTests
//
// Tests for Set-Cookie rewriting, Location rewriting, and Origin/Referer rewriting
// in RecordingProxyService reverse-proxy mode.

final class ProxyHeaderRewriterTests: XCTestCase {

    private let upstream = URL(string: "https://eularix.com")!
    private let localPort: UInt16 = 8080
    private var sut: RecordingProxyService!

    private var reverseMode: ProxyMode {
        .reverse(rules: [UpstreamRule(pathPrefix: "/", upstream: upstream)])
    }

    override func setUp() async throws {
        try await super.setUp()
        // RecordingProxyService is @MainActor — instantiate on main actor.
        sut = await MainActor.run { RecordingProxyService() }
    }

    // MARK: - Set-Cookie: Domain strip

    func test_setCookie_domainStripped() {
        let input = "session=abc123; Path=/; Domain=eularix.com; HttpOnly"
        let result = sut.rewriteSetCookie(input)
        XCTAssertFalse(result.lowercased().contains("domain="), "Domain= attribute must be stripped")
        XCTAssertTrue(result.contains("session=abc123"))
        XCTAssertTrue(result.contains("HttpOnly"))
    }

    // MARK: - Set-Cookie: Secure strip

    func test_setCookie_secureStripped() {
        let input = "token=xyz; Path=/; Secure; HttpOnly"
        let result = sut.rewriteSetCookie(input)
        let parts = result.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertFalse(parts.contains("Secure"), "Secure flag must be stripped for localhost")
        XCTAssertTrue(parts.contains("HttpOnly"))
    }

    // MARK: - Set-Cookie: SameSite=Strict → SameSite=Lax

    func test_setCookie_sameSiteStrictRemapped() {
        let input = "csrf=tok; SameSite=Strict; Path=/"
        let result = sut.rewriteSetCookie(input)
        XCTAssertTrue(result.contains("SameSite=Lax"), "SameSite=Strict should become SameSite=Lax")
        XCTAssertFalse(result.lowercased().contains("samesite=strict"))
    }

    // MARK: - Multiple Set-Cookie split

    func test_splitSetCookie_singleCookie() {
        let raw = "a=1; Path=/"
        let result = sut.splitSetCookieHeader(raw)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], "a=1; Path=/")
    }

    func test_splitSetCookie_twoCookies() {
        // HTTPURLResponse merges with ", "
        let raw = "a=1; Path=/, b=2; Path=/"
        let result = sut.splitSetCookieHeader(raw)
        XCTAssertEqual(result.count, 2, "Should split into 2 cookies, got: \(result)")
        XCTAssertTrue(result[0].contains("a=1"))
        XCTAssertTrue(result[1].contains("b=2"))
    }

    func test_splitSetCookie_expiresCommaNotSplit() {
        // "Thu, 01 Jan 2099" comma inside Expires should NOT split
        let raw = "session=abc; Expires=Thu, 01 Jan 2099 00:00:00 GMT; Path=/"
        let result = sut.splitSetCookieHeader(raw)
        XCTAssertEqual(result.count, 1, "Expires date comma must not cause a split, got: \(result)")
    }

    func test_splitSetCookie_expiresCommaFollowedByNewCookie() {
        let raw = "a=1; Expires=Thu, 01 Jan 2099 00:00:00 GMT; Path=/, b=2; Path=/"
        let result = sut.splitSetCookieHeader(raw)
        XCTAssertEqual(result.count, 2, "Should have 2 cookies (1 with Expires), got: \(result)")
        XCTAssertTrue(result[0].contains("a=1"))
        XCTAssertTrue(result[1].contains("b=2"))
    }

    // MARK: - Location rewriter: absolute → relative

    func test_location_absoluteSameHost_becomesRelative() {
        let result = sut.rewriteLocation("https://eularix.com/dashboard", upstream: upstream)
        XCTAssertEqual(result, "/dashboard")
    }

    func test_location_absoluteSameHostWithQuery_becomesRelative() {
        let result = sut.rewriteLocation("https://eularix.com/search?q=test", upstream: upstream)
        XCTAssertEqual(result, "/search?q=test")
    }

    func test_location_differentHost_unchanged() {
        let result = sut.rewriteLocation("https://other.com/page", upstream: upstream)
        XCTAssertEqual(result, "https://other.com/page", "Different host must not be rewritten")
    }

    func test_location_relativeAlready_unchanged() {
        let result = sut.rewriteLocation("/already/relative", upstream: upstream)
        XCTAssertEqual(result, "/already/relative")
    }

    // MARK: - Origin rewrite

    func test_requestHeaders_originRewritten() {
        let headers: [(String, String)] = [("Origin", "http://localhost:8080")]
        let result = sut.rewriteRequestHeaders(
            headers,
            upstream: upstream,
            mode: reverseMode
        )
        let origin = result.first(where: { $0.0.lowercased() == "origin" })?.1
        XCTAssertEqual(origin, "https://eularix.com", "Origin header must be rewritten to upstream")
    }

    func test_requestHeaders_refererRewritten() {
        let headers: [(String, String)] = [("Referer", "http://localhost:8080/some/page")]
        let result = sut.rewriteRequestHeaders(
            headers,
            upstream: upstream,
            mode: reverseMode
        )
        let referer = result.first(where: { $0.0.lowercased() == "referer" })?.1
        XCTAssertNotNil(referer)
        XCTAssertTrue(referer!.hasPrefix("https://eularix.com"), "Referer must be rewritten to upstream origin")
    }

    func test_requestHeaders_hopByHopStripped() {
        let headers: [(String, String)] = [
            ("Connection", "keep-alive"),
            ("Keep-Alive", "timeout=5"),
            ("Transfer-Encoding", "chunked"),
            ("Accept", "application/json")
        ]
        let result = sut.rewriteRequestHeaders(
            headers,
            upstream: upstream,
            mode: reverseMode
        )
        let keys = result.map { $0.0.lowercased() }
        XCTAssertFalse(keys.contains("connection"))
        XCTAssertFalse(keys.contains("keep-alive"))
        XCTAssertFalse(keys.contains("transfer-encoding"))
        XCTAssertTrue(keys.contains("accept"))
    }

    func test_requestHeaders_hostInjectedInReverseMode() {
        let result = sut.rewriteRequestHeaders(
            [],
            upstream: upstream,
            mode: reverseMode
        )
        let host = result.first(where: { $0.0.lowercased() == "host" })?.1
        XCTAssertEqual(host, "eularix.com")
    }

    func test_requestHeaders_forwardModeNoHostInjection() {
        let result = sut.rewriteRequestHeaders(
            [("Accept", "text/html")],
            upstream: URL(string: "http://example.com/")!,
            mode: .forward
        )
        let keys = result.map { $0.0.lowercased() }
        XCTAssertFalse(keys.contains("host"), "Forward mode must not inject Host")
    }
}
