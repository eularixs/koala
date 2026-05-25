import XCTest
@testable import koala

final class HARImporterTests: XCTestCase {

    // MARK: - Fixtures

    private let basicHAR = """
    {
      "log": {
        "creator": { "name": "Chrome DevTools" },
        "entries": [
          {
            "request": {
              "method": "GET",
              "url": "https://api.example.com/users?page=1",
              "headers": [
                { "name": "Accept", "value": "application/json" }
              ],
              "queryString": [
                { "name": "page", "value": "1" }
              ]
            }
          },
          {
            "request": {
              "method": "POST",
              "url": "https://api.example.com/login",
              "headers": [
                { "name": "Content-Type", "value": "application/json" }
              ],
              "queryString": [],
              "postData": {
                "mimeType": "application/json",
                "text": "{\\"username\\": \\"alice\\"}"
              }
            }
          },
          {
            "request": {
              "method": "GET",
              "url": "https://api.example.com/secure",
              "headers": [
                { "name": "Authorization", "value": "Bearer abc123" }
              ],
              "queryString": []
            }
          },
          {
            "request": {
              "method": "GET",
              "url": "https://api.example.com/basic-auth",
              "headers": [
                { "name": "Authorization", "value": "Basic dXNlcjpwYXNz" }
              ],
              "queryString": []
            }
          }
        ]
      }
    }
    """

    // MARK: - Tests

    func test_collectionNameFromCreator() throws {
        let data = try XCTUnwrap(basicHAR.data(using: .utf8))
        let collection = try HARImporter.parse(data: data)
        XCTAssertEqual(collection.name, "Chrome DevTools")
    }

    func test_entryCountMatches() throws {
        let data = try XCTUnwrap(basicHAR.data(using: .utf8))
        let collection = try HARImporter.parse(data: data)
        XCTAssertEqual(collection.items.count, 4)
    }

    func test_queryParamsMapped() throws {
        let data = try XCTUnwrap(basicHAR.data(using: .utf8))
        let collection = try HARImporter.parse(data: data)
        guard case .request(let req) = collection.items[0] else { return XCTFail() }
        XCTAssertEqual(req.queryParams.count, 1)
        XCTAssertEqual(req.queryParams[0].key, "page")
    }

    func test_bearerAuthExtracted() throws {
        let data = try XCTUnwrap(basicHAR.data(using: .utf8))
        let collection = try HARImporter.parse(data: data)
        guard case .request(let req) = collection.items[2] else { return XCTFail() }
        guard case .bearer(let token) = req.auth else { return XCTFail("Expected bearer") }
        XCTAssertEqual(token, "abc123")
        // Authorization header should not appear in headers
        XCTAssertFalse(req.headers.contains(where: { $0.key.lowercased() == "authorization" }))
    }

    func test_basicAuthExtracted() throws {
        let data = try XCTUnwrap(basicHAR.data(using: .utf8))
        let collection = try HARImporter.parse(data: data)
        guard case .request(let req) = collection.items[3] else { return XCTFail() }
        guard case .basic(let user, let pass) = req.auth else { return XCTFail("Expected basic") }
        XCTAssertEqual(user, "user")
        XCTAssertEqual(pass, "pass")
    }
}
