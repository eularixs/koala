import XCTest
@testable import koala

// MARK: - ProxyModeCodableTests

final class ProxyModeCodableTests: XCTestCase {

    // MARK: - Old single-upstream format migration

    func test_oldSingleUpstreamFormat_decodesAsOneRule() throws {
        // Simulate old UserDefaults value: {type:"reverse", upstream:"https://eularix.com"}
        let json = #"{"type":"reverse","upstream":"https://eularix.com"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProxyMode.self, from: data)
        guard case .reverse(let rules) = decoded else {
            XCTFail("Expected .reverse, got \(decoded)"); return
        }
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].pathPrefix, "/")
        XCTAssertEqual(rules[0].upstream.absoluteString, "https://eularix.com")
    }

    // MARK: - New multi-rule format roundtrip

    func test_multiRuleFormat_roundtrip() throws {
        let original = ProxyMode.reverse(rules: [
            UpstreamRule(pathPrefix: "/__auth", upstream: URL(string: "https://api.auth.eularix.com")!),
            UpstreamRule(pathPrefix: "/__api",  upstream: URL(string: "https://api.eularix.com")!),
            UpstreamRule(pathPrefix: "/",        upstream: URL(string: "https://eularix.com")!),
        ])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyMode.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Forward mode roundtrip

    func test_forwardMode_roundtrip() throws {
        let original = ProxyMode.forward
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyMode.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - UpstreamRule roundtrip

    func test_upstreamRule_roundtrip() throws {
        let rule = UpstreamRule(pathPrefix: "/__auth", upstream: URL(string: "https://api.auth.eularix.com")!)
        let encoded = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(UpstreamRule.self, from: encoded)
        XCTAssertEqual(rule.pathPrefix, decoded.pathPrefix)
        XCTAssertEqual(rule.upstream, decoded.upstream)
    }

    // MARK: - CaptureFilter roundtrip

    func test_captureFilter_roundtrip() throws {
        let filter = CaptureFilter(skipStaticAssets: true, pathGlobs: ["/api/**", "/__auth/**"])
        let encoded = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(CaptureFilter.self, from: encoded)
        XCTAssertEqual(filter, decoded)
    }

    func test_captureFilter_defaults() {
        let filter = CaptureFilter()
        XCTAssertTrue(filter.skipStaticAssets)
        XCTAssertTrue(filter.pathGlobs.isEmpty)
    }
}
