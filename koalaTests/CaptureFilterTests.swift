import XCTest
@testable import koala

// MARK: - CaptureFilterTests

final class CaptureFilterTests: XCTestCase {

    private var sut: RecordingProxyService!

    override func setUp() async throws {
        try await super.setUp()
        sut = await MainActor.run { RecordingProxyService() }
    }

    // MARK: - isStaticAsset

    func test_isStaticAsset_html() {
        XCTAssertTrue(sut.testIsStaticAsset("text/html; charset=utf-8"))
    }

    func test_isStaticAsset_css() {
        XCTAssertTrue(sut.testIsStaticAsset("text/css"))
    }

    func test_isStaticAsset_javascript() {
        XCTAssertTrue(sut.testIsStaticAsset("application/javascript"))
        XCTAssertTrue(sut.testIsStaticAsset("text/javascript"))
    }

    func test_isStaticAsset_image() {
        XCTAssertTrue(sut.testIsStaticAsset("image/png"))
        XCTAssertTrue(sut.testIsStaticAsset("image/svg+xml"))
    }

    func test_isStaticAsset_font() {
        XCTAssertTrue(sut.testIsStaticAsset("font/woff2"))
        XCTAssertTrue(sut.testIsStaticAsset("application/font-woff"))
    }

    func test_isStaticAsset_json_notStatic() {
        XCTAssertFalse(sut.testIsStaticAsset("application/json"))
    }

    func test_isStaticAsset_apiResponse_notStatic() {
        XCTAssertFalse(sut.testIsStaticAsset("application/vnd.api+json"))
    }

    // MARK: - Static asset skip

    func test_shouldCapture_skipStaticAssets_htmlNotCaptured() {
        let filter = CaptureFilter(skipStaticAssets: true, pathGlobs: [])
        XCTAssertFalse(sut.testShouldCapture(path: "/index.html", contentType: "text/html", filter: filter))
    }

    func test_shouldCapture_skipStaticAssets_jsonCaptured() {
        let filter = CaptureFilter(skipStaticAssets: true, pathGlobs: [])
        XCTAssertTrue(sut.testShouldCapture(path: "/api/users", contentType: "application/json", filter: filter))
    }

    func test_shouldCapture_skipStaticAssetsOff_htmlCaptured() {
        let filter = CaptureFilter(skipStaticAssets: false, pathGlobs: [])
        XCTAssertTrue(sut.testShouldCapture(path: "/index.html", contentType: "text/html", filter: filter))
    }

    // MARK: - Path glob include

    func test_shouldCapture_pathGlob_matchingPathCaptured() {
        let filter = CaptureFilter(skipStaticAssets: false, pathGlobs: ["/api/**"])
        XCTAssertTrue(sut.testShouldCapture(path: "/api/users", contentType: "application/json", filter: filter))
    }

    func test_shouldCapture_pathGlob_nonMatchingPathNotCaptured() {
        let filter = CaptureFilter(skipStaticAssets: false, pathGlobs: ["/api/**"])
        XCTAssertFalse(sut.testShouldCapture(path: "/static/app.js", contentType: "application/javascript", filter: filter))
    }

    func test_shouldCapture_multipleGlobs_anyMatchCaptures() {
        let filter = CaptureFilter(skipStaticAssets: false, pathGlobs: ["/api/**", "/__auth/**"])
        XCTAssertTrue(sut.testShouldCapture(path: "/__auth/sign-in", contentType: "application/json", filter: filter))
        XCTAssertTrue(sut.testShouldCapture(path: "/api/v2/users", contentType: "application/json", filter: filter))
        XCTAssertFalse(sut.testShouldCapture(path: "/about", contentType: "text/html", filter: filter))
    }

    // MARK: - Empty globs = capture all (respecting skipStaticAssets)

    func test_shouldCapture_noGlobs_capturesAll() {
        let filter = CaptureFilter(skipStaticAssets: false, pathGlobs: [])
        XCTAssertTrue(sut.testShouldCapture(path: "/anything", contentType: "application/json", filter: filter))
        XCTAssertTrue(sut.testShouldCapture(path: "/static/app.js", contentType: "application/javascript", filter: filter))
    }

    // MARK: - Glob matching

    func test_glob_doubleStarMatchesSlashes() {
        XCTAssertTrue(sut.testPathMatchesGlob("/api/v1/users", glob: "/api/**"))
        XCTAssertTrue(sut.testPathMatchesGlob("/api/users", glob: "/api/**"))
    }

    func test_glob_singleStarDoesNotMatchSlash() {
        XCTAssertTrue(sut.testPathMatchesGlob("/api/users", glob: "/api/*"))
        XCTAssertFalse(sut.testPathMatchesGlob("/api/v1/users", glob: "/api/*"))
    }

    func test_glob_exactPathMatches() {
        XCTAssertTrue(sut.testPathMatchesGlob("/api/users", glob: "/api/users"))
        XCTAssertFalse(sut.testPathMatchesGlob("/api/posts", glob: "/api/users"))
    }
}
