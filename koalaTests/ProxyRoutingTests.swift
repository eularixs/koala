import XCTest
@testable import koala

// MARK: - ProxyRoutingTests
//
// Tests for multi-upstream path-prefix routing in RecordingProxyService.

final class ProxyRoutingTests: XCTestCase {

    private var sut: RecordingProxyService!

    private let authURL = URL(string: "https://api.auth.eularix.com")!
    private let apiURL  = URL(string: "https://api.eularix.com")!
    private let rootURL = URL(string: "https://eularix.com")!

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

    // MARK: - Single rule "/"

    func test_singleRule_catchAll_matchesRoot() {
        let rules = [UpstreamRule(pathPrefix: "/", upstream: rootURL)]
        let resolved = sut.resolveUpstream(path: "/", rules: rules)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.host, "eularix.com")
    }

    func test_singleRule_catchAll_matchesDeepPath() {
        let rules = [UpstreamRule(pathPrefix: "/", upstream: rootURL)]
        let resolved = sut.resolveUpstream(path: "/some/deep/path", rules: rules)
        XCTAssertEqual(resolved?.path, "/some/deep/path")
        XCTAssertEqual(resolved?.host, "eularix.com")
    }

    // MARK: - Multi-rule longest-prefix wins

    func test_multiRule_authPrefix_routesToAuthUpstream() {
        let resolved = sut.resolveUpstream(path: "/__auth/sign-in", rules: multiRules)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.host, "api.auth.eularix.com")
        XCTAssertEqual(resolved?.path, "/sign-in")
    }

    func test_multiRule_apiPrefix_routesToApiUpstream() {
        let resolved = sut.resolveUpstream(path: "/__api/users", rules: multiRules)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.host, "api.eularix.com")
        XCTAssertEqual(resolved?.path, "/users")
    }

    func test_multiRule_rootPath_routesToRootUpstream() {
        let resolved = sut.resolveUpstream(path: "/", rules: multiRules)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.host, "eularix.com")
    }

    func test_multiRule_nonPrefixedPath_routesToCatchAll() {
        let resolved = sut.resolveUpstream(path: "/about", rules: multiRules)
        XCTAssertEqual(resolved?.host, "eularix.com")
        XCTAssertEqual(resolved?.path, "/about")
    }

    // MARK: - Query string preserved

    func test_queryStringPreserved_authRoute() {
        let resolved = sut.resolveUpstream(path: "/__auth/sign-in?next=/dashboard", rules: multiRules)
        XCTAssertEqual(resolved?.host, "api.auth.eularix.com")
        XCTAssertEqual(resolved?.path, "/sign-in")
        XCTAssertEqual(resolved?.query, "next=/dashboard")
    }

    func test_queryStringPreserved_catchAll() {
        let resolved = sut.resolveUpstream(path: "/page?ref=home", rules: multiRules)
        XCTAssertEqual(resolved?.host, "eularix.com")
        XCTAssertEqual(resolved?.query, "ref=home")
    }

    // MARK: - Prefix matching edge cases

    func test_prefixExactMatch_noTrailingSlash() {
        let resolved = sut.resolveUpstream(path: "/__auth", rules: multiRules)
        XCTAssertEqual(resolved?.host, "api.auth.eularix.com")
    }

    func test_prefixDoesNotMatchSimilarSuffix() {
        // "/__authz" must NOT match "/__auth" — falls through to "/"
        let resolved = sut.resolveUpstream(path: "/__authz/something", rules: multiRules)
        XCTAssertEqual(resolved?.host, "eularix.com")
    }

    // MARK: - pathMatchesPrefix helper

    func test_pathMatchesPrefix_slashAlwaysMatches() {
        XCTAssertTrue(sut.testPathMatchesPrefix("/anything", prefix: "/"))
        XCTAssertTrue(sut.testPathMatchesPrefix("/", prefix: "/"))
    }

    func test_pathMatchesPrefix_exactMatch() {
        XCTAssertTrue(sut.testPathMatchesPrefix("/__auth", prefix: "/__auth"))
    }

    func test_pathMatchesPrefix_withSubpath() {
        XCTAssertTrue(sut.testPathMatchesPrefix("/__auth/login", prefix: "/__auth"))
    }

    func test_pathMatchesPrefix_doesNotMatchSuffix() {
        XCTAssertFalse(sut.testPathMatchesPrefix("/__authz", prefix: "/__auth"))
    }
}
