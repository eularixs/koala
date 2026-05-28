import XCTest
@testable import koala

final class RequestGroupingEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeCapture(
        method: String,
        url: String,
        body: Data? = nil,
        capturedAt: Date = Date()
    ) -> RecordedRequest {
        RecordedRequest(
            capturedAt: capturedAt,
            method: method,
            url: url,
            headers: [:],
            requestBody: body,
            responseStatus: 200
        )
    }

    // MARK: - Basic grouping

    func test_groupsByFirstPathSegment() {
        let captures = [
            makeCapture(method: "GET",  url: "http://example.com/management-assets/get-transaction?id=1"),
            makeCapture(method: "POST", url: "http://example.com/management-assets/create-asset"),
            makeCapture(method: "GET",  url: "http://example.com/users/list"),
            makeCapture(method: "GET",  url: "http://example.com/users/profile/123"),
        ]
        let result = RequestGroupingEngine.group(captures)

        XCTAssertEqual(result.count, 2)
        let names = result.map(\.name)
        XCTAssertTrue(names.contains("management-assets"), "Expected 'management-assets' collection")
        XCTAssertTrue(names.contains("users"), "Expected 'users' collection")

        let assets = result.first(where: { $0.name == "management-assets" })!
        XCTAssertEqual(assets.requests.count, 2)

        let users = result.first(where: { $0.name == "users" })!
        XCTAssertEqual(users.requests.count, 2)
    }

    // MARK: - :id normalization

    func test_numericSegmentNormalizedToId() {
        let captures = [
            makeCapture(method: "GET", url: "http://example.com/users/profile/123"),
        ]
        let result = RequestGroupingEngine.group(captures)
        let userCollection = result.first(where: { $0.name == "users" })!
        let req = userCollection.requests.first!
        XCTAssertEqual(req.name, "profile/:id")
    }

    func test_uuidSegmentNormalizedToId() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let captures = [
            makeCapture(method: "GET", url: "http://example.com/orders/\(uuid)/details"),
        ]
        let result = RequestGroupingEngine.group(captures)
        let req = result.first!.requests.first!
        XCTAssertEqual(req.name, ":id/details")
    }

    func test_collectionNameIsNotNormalized() {
        // First segment should remain as-is, even if numeric (edge case)
        let captures = [
            makeCapture(method: "GET", url: "http://example.com/v2/users"),
        ]
        let result = RequestGroupingEngine.group(captures)
        XCTAssertEqual(result.first?.name, "v2", "Collection name should not be normalized")
    }

    // MARK: - Deduplication

    func test_dedupSameMethodAndNormalizedPath_keepsLatest() {
        let early = Date(timeIntervalSinceNow: -60)
        let late  = Date()
        let captures = [
            makeCapture(method: "GET", url: "http://example.com/users/42", capturedAt: early),
            makeCapture(method: "GET", url: "http://example.com/users/99", capturedAt: late),
        ]
        let result = RequestGroupingEngine.group(captures)
        let users = result.first(where: { $0.name == "users" })!
        // Both normalize to GET|:id — only 1 entry kept (the later one)
        XCTAssertEqual(users.requests.count, 1)
        XCTAssertEqual(users.requests.first?.url, "http://example.com/users/99")
    }

    func test_differentMethodsSamePathAreNotDeduped() {
        let captures = [
            makeCapture(method: "GET",    url: "http://example.com/items/1"),
            makeCapture(method: "DELETE", url: "http://example.com/items/2"),
        ]
        let result = RequestGroupingEngine.group(captures)
        let items = result.first(where: { $0.name == "items" })!
        XCTAssertEqual(items.requests.count, 2)
    }

    // MARK: - Sensitive header redaction

    func test_authorizationHeaderRedacted() {
        var capture = makeCapture(method: "GET", url: "http://example.com/api/data")
        capture = RecordedRequest(
            method: "GET",
            url: "http://example.com/api/data",
            headers: ["Authorization": "Bearer secret", "Content-Type": "application/json"],
            responseStatus: 200
        )
        let result = RequestGroupingEngine.group([capture])
        let req = result.first!.requests.first!
        let authHeader = req.headers.first(where: { $0.key == "Authorization" })
        XCTAssertEqual(authHeader?.value, "<redacted>")
        let ctHeader = req.headers.first(where: { $0.key == "Content-Type" })
        XCTAssertEqual(ctHeader?.value, "application/json")
    }

    // MARK: - Edge: root-level path (no collection segment)

    func test_rootPathRequestsAreSkipped() {
        let captures = [
            makeCapture(method: "GET", url: "http://example.com/"),
            makeCapture(method: "GET", url: "http://example.com"),
        ]
        let result = RequestGroupingEngine.group(captures)
        XCTAssertTrue(result.isEmpty, "Requests with no path segments should be skipped")
    }

    // MARK: - isIdSegment unit tests

    func test_isIdSegment_numeric() {
        XCTAssertTrue(RequestGroupingEngine.isIdSegment("123"))
        XCTAssertTrue(RequestGroupingEngine.isIdSegment("0"))
        XCTAssertFalse(RequestGroupingEngine.isIdSegment("abc"))
        XCTAssertFalse(RequestGroupingEngine.isIdSegment("12abc"))
    }

    func test_isIdSegment_uuid() {
        XCTAssertTrue(RequestGroupingEngine.isIdSegment("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertFalse(RequestGroupingEngine.isIdSegment("not-a-uuid"))
    }
}
