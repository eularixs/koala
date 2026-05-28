import XCTest
@testable import koala

// MARK: - BodyRewriterMultiUpstreamTests
//
// Tests for multi-upstream body URL rewriting.

final class BodyRewriterMultiUpstreamTests: XCTestCase {

    private var sut: RecordingProxyService!

    private let authURL = URL(string: "https://api.auth.eularix.com")!
    private let apiURL  = URL(string: "https://api.eularix.com")!
    private let rootURL = URL(string: "https://eularix.com")!
    private let port: UInt16 = 8888

    override func setUp() async throws {
        try await super.setUp()
        sut = await MainActor.run { RecordingProxyService() }
    }

    private var multiRules: [UpstreamRule] {
        [
            UpstreamRule(pathPrefix: "/__auth", upstream: authURL),
            UpstreamRule(pathPrefix: "/__api",  upstream: apiURL),
            UpstreamRule(pathPrefix: "/",        upstream: rootURL),
        ]
    }

    private func rewrite(_ html: String, rules: [UpstreamRule]? = nil) -> String {
        let r = rules ?? multiRules
        let data = html.data(using: .utf8)!
        let result = sut.rewriteBodyMulti(data, contentType: "text/html", rules: r, localPort: port)
        return String(data: result, encoding: .utf8) ?? ""
    }

    // MARK: - Replaces all three upstreams in one HTML

    func test_rewritesAllThreeUpstreams() {
        let html = """
        <script>
          var authBase = "https://api.auth.eularix.com";
          var apiBase  = "https://api.eularix.com";
          var siteBase = "https://eularix.com";
        </script>
        """
        let result = rewrite(html)
        XCTAssertTrue(result.contains("http://localhost:8888/__auth"), "auth upstream not rewritten")
        XCTAssertTrue(result.contains("http://localhost:8888/__api"),  "api upstream not rewritten")
        XCTAssertTrue(result.contains("http://localhost:8888\""),      "root upstream not rewritten")
        XCTAssertFalse(result.contains("api.auth.eularix.com"), "auth upstream still present")
        XCTAssertFalse(result.contains("api.eularix.com"),      "api upstream still present")
    }

    // MARK: - Longer upstream rewritten before shorter (no partial match)

    func test_longerUpstreamRewrittenFirst_noPartialMatch() {
        // If we rewrote "eularix.com" first, it would also match inside "api.eularix.com"
        // which would produce "api.http://localhost:8888" — wrong. Longer-first prevents this.
        let html = "<a href=\"https://api.eularix.com/v1\">link</a>"
        let result = rewrite(html)
        XCTAssertTrue(result.contains("http://localhost:8888/__api/v1"))
        XCTAssertFalse(result.contains("api.http://localhost"))
    }

    // MARK: - Scheme-less // rewrite

    func test_schemeRelativeURLRewritten() {
        let html = "<img src=\"//api.auth.eularix.com/avatar.png\">"
        let result = rewrite(html)
        XCTAssertTrue(result.contains("//localhost:8888/__auth/avatar.png"),
                      "scheme-relative URL should be rewritten, got: \(result)")
    }

    // MARK: - Catch-all "/" prefix produces no extra slash

    func test_rootPrefixNoDoubleSlash() {
        let html = "<link rel=\"canonical\" href=\"https://eularix.com/about\">"
        let result = rewrite(html)
        XCTAssertTrue(result.contains("http://localhost:8888/about"), "got: \(result)")
        XCTAssertFalse(result.contains("localhost:8888//about"), "double slash in: \(result)")
    }

    // MARK: - Non-text content type not rewritten

    func test_binaryContentType_notRewritten() {
        let html = "https://eularix.com/image.png"
        let data = html.data(using: .utf8)!
        let result = sut.rewriteBodyMulti(data, contentType: "image/png", rules: multiRules, localPort: port)
        let str = String(data: result, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("https://eularix.com/image.png"), "binary body should not be rewritten")
    }

    // MARK: - Single rule backward compat

    func test_singleRule_rewriteWorks() {
        let rules = [UpstreamRule(pathPrefix: "/", upstream: rootURL)]
        let html = "<a href=\"https://eularix.com/contact\">Contact</a>"
        let result = rewrite(html, rules: rules)
        XCTAssertTrue(result.contains("http://localhost:8888/contact"), "got: \(result)")
    }
}
