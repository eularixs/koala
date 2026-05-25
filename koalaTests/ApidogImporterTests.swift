import XCTest
@testable import koala

final class ApidogImporterTests: XCTestCase {

    // MARK: - Fixtures

    private let openAPIFixture = """
    {
      "openapi": "3.0.0",
      "info": { "title": "Apidog API", "version": "1.0.0" },
      "servers": [{ "url": "https://api.example.com" }],
      "paths": {
        "/pets": {
          "get": {
            "summary": "List Pets",
            "tags": ["Pets"],
            "parameters": [
              { "name": "limit", "in": "query", "required": true, "example": "10" }
            ],
            "responses": { "200": { "description": "OK" } }
          },
          "post": {
            "summary": "Create Pet",
            "tags": ["Pets"],
            "requestBody": {
              "content": {
                "application/json": {
                  "example": { "name": "Fido" }
                }
              }
            },
            "responses": { "201": { "description": "Created" } }
          }
        }
      }
    }
    """

    private let nativeFixture = """
    {
      "apidoc": {
        "name": "Native Apidog",
        "folders": [
          { "id": "f1", "name": "Users" }
        ],
        "endpoints": [
          {
            "name": "Get Users",
            "method": "GET",
            "path": "/users",
            "folderId": "f1",
            "queryParams": [{ "name": "page", "value": "1" }],
            "headers": []
          },
          {
            "name": "Create User",
            "method": "POST",
            "path": "/users",
            "folderId": "f1",
            "headers": [],
            "requestBody": {
              "type": "json",
              "jsonBody": "{\\"email\\": \\"a@b.com\\"}"
            }
          }
        ]
      }
    }
    """

    // MARK: - Tests

    func test_openAPI_collectionName() throws {
        let data = try XCTUnwrap(openAPIFixture.data(using: .utf8))
        let collection = try ApidogImporter.parse(data: data)
        XCTAssertEqual(collection.name, "Apidog API")
    }

    func test_openAPI_folderGrouping() throws {
        let data = try XCTUnwrap(openAPIFixture.data(using: .utf8))
        let collection = try ApidogImporter.parse(data: data)
        XCTAssertEqual(collection.items.count, 1)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder")
        }
        XCTAssertEqual(folder.name, "Pets")
        XCTAssertEqual(folder.items.count, 2)
    }

    func test_openAPI_queryParamMapped() throws {
        let data = try XCTUnwrap(openAPIFixture.data(using: .utf8))
        let collection = try ApidogImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0],
              case .request(let req) = folder.items[0] else { return XCTFail() }
        XCTAssertFalse(req.queryParams.isEmpty)
        XCTAssertEqual(req.queryParams[0].key, "limit")
    }

    func test_native_collectionName() throws {
        let data = try XCTUnwrap(nativeFixture.data(using: .utf8))
        let collection = try ApidogImporter.parse(data: data)
        XCTAssertEqual(collection.name, "Native Apidog")
    }

    func test_native_folderAndRequests() throws {
        let data = try XCTUnwrap(nativeFixture.data(using: .utf8))
        let collection = try ApidogImporter.parse(data: data)
        guard case .folder(let folder) = collection.items.first(where: { if case .folder = $0 { return true }; return false }) else {
            return XCTFail("Expected Users folder")
        }
        XCTAssertEqual(folder.name, "Users")
        XCTAssertEqual(folder.items.count, 2)
    }
}
