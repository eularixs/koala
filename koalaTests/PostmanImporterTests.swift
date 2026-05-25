import XCTest
@testable import koala

final class PostmanImporterTests: XCTestCase {

    // MARK: - Fixtures

    /// Minimal v2.1 JSON covering: nested folder, GET with query params,
    /// POST with raw JSON body, and request with bearer auth.
    private let minimalJSON = """
    {
      "info": {
        "name": "Test Collection",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "item": [
        {
          "name": "Users",
          "item": [
            {
              "name": "Get Users",
              "request": {
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "https://api.example.com/users?page=1&limit=20",
                  "query": [
                    { "key": "page", "value": "1" },
                    { "key": "limit", "value": "20" }
                  ]
                }
              }
            },
            {
              "name": "Create User",
              "request": {
                "method": "POST",
                "header": [
                  { "key": "Content-Type", "value": "application/json" }
                ],
                "url": { "raw": "https://api.example.com/users" },
                "body": {
                  "mode": "raw",
                  "raw": "{\\"name\\": \\"Alice\\", \\"email\\": \\"alice@example.com\\"}",
                  "options": { "raw": { "language": "json" } }
                }
              }
            }
          ]
        },
        {
          "name": "Secure Endpoint",
          "request": {
            "method": "GET",
            "header": [],
            "url": { "raw": "https://api.example.com/secure" },
            "auth": {
              "type": "bearer",
              "bearer": [
                { "key": "token", "value": "my-secret-token" }
              ]
            }
          }
        }
      ]
    }
    """

    // MARK: - Tests

    func test_collectionName() throws {
        let data = try XCTUnwrap(minimalJSON.data(using: .utf8))
        let collection = try PostmanImporter.parse(data: data)
        XCTAssertEqual(collection.name, "Test Collection")
    }

    func test_topLevelItemCount() throws {
        let data = try XCTUnwrap(minimalJSON.data(using: .utf8))
        let collection = try PostmanImporter.parse(data: data)
        // 1 folder ("Users") + 1 request ("Secure Endpoint")
        XCTAssertEqual(collection.items.count, 2)
    }

    func test_nestedFolder() throws {
        let data = try XCTUnwrap(minimalJSON.data(using: .utf8))
        let collection = try PostmanImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder at index 0")
        }
        XCTAssertEqual(folder.name, "Users")
        XCTAssertEqual(folder.items.count, 2)
    }

    func test_getRequestWithQueryParams() throws {
        let data = try XCTUnwrap(minimalJSON.data(using: .utf8))
        let collection = try PostmanImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0],
              case .request(let req) = folder.items[0] else {
            return XCTFail("Expected GET request inside folder")
        }
        XCTAssertEqual(req.name, "Get Users")
        XCTAssertEqual(req.method.rawValue, "GET")
        XCTAssertEqual(req.queryParams.count, 2)
        XCTAssertEqual(req.queryParams[0].key, "page")
        XCTAssertEqual(req.queryParams[0].value, "1")
        XCTAssertEqual(req.queryParams[1].key, "limit")
        XCTAssertEqual(req.queryParams[1].value, "20")
    }

    func test_postWithRawJSONBody() throws {
        let data = try XCTUnwrap(minimalJSON.data(using: .utf8))
        let collection = try PostmanImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0],
              case .request(let req) = folder.items[1] else {
            return XCTFail("Expected POST request inside folder")
        }
        XCTAssertEqual(req.method.rawValue, "POST")
        guard case .json(let body) = req.body else {
            return XCTFail("Expected JSON body")
        }
        XCTAssertTrue(body.contains("Alice"))
    }

    func test_bearerAuth() throws {
        let data = try XCTUnwrap(minimalJSON.data(using: .utf8))
        let collection = try PostmanImporter.parse(data: data)
        guard case .request(let req) = collection.items[1] else {
            return XCTFail("Expected request at index 1")
        }
        guard case .bearer(let token) = req.auth else {
            return XCTFail("Expected bearer auth")
        }
        XCTAssertEqual(token, "my-secret-token")
    }

    func test_invalidJSON_throws() {
        let badData = "not valid json".data(using: .utf8)!
        XCTAssertThrowsError(try PostmanImporter.parse(data: badData)) { error in
            guard case ImportError.malformed = error else {
                XCTFail("Expected ImportError.malformed, got \(error)")
                return
            }
        }
    }

    func test_wrongVersion_throws() throws {
        let v20 = """
        {
          "info": {
            "name": "Old",
            "schema": "https://schema.getpostman.com/json/collection/v2.0.0/collection.json"
          },
          "item": []
        }
        """
        let data = try XCTUnwrap(v20.data(using: .utf8))
        XCTAssertThrowsError(try PostmanImporter.parse(data: data)) { error in
            guard case ImportError.unsupportedVersion = error else {
                XCTFail("Expected ImportError.unsupportedVersion, got \(error)")
                return
            }
        }
    }
}
