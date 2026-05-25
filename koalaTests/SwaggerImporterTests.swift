import XCTest
@testable import koala

final class SwaggerImporterTests: XCTestCase {

    // MARK: - Fixtures

    private let swagger20 = """
    {
      "swagger": "2.0",
      "info": { "title": "Pet Store", "version": "1.0" },
      "host": "petstore.example.com",
      "basePath": "/api",
      "schemes": ["https"],
      "paths": {
        "/pets": {
          "get": {
            "summary": "List Pets",
            "tags": ["pets"],
            "parameters": [
              { "name": "limit", "in": "query", "required": false }
            ],
            "responses": { "200": { "description": "OK" } }
          },
          "post": {
            "summary": "Create Pet",
            "tags": ["pets"],
            "parameters": [
              {
                "name": "body",
                "in": "body",
                "required": true,
                "schema": {}
              }
            ],
            "responses": { "201": { "description": "Created" } }
          }
        },
        "/pets/{id}": {
          "get": {
            "summary": "Get Pet",
            "tags": ["pets"],
            "parameters": [
              { "name": "X-Custom", "in": "header", "required": false }
            ],
            "security": [{ "apiKeyAuth": [] }],
            "responses": { "200": { "description": "OK" } }
          }
        }
      },
      "securityDefinitions": {
        "apiKeyAuth": {
          "type": "apiKey",
          "name": "X-API-Key",
          "in": "header"
        }
      }
    }
    """

    // MARK: - Tests

    func test_collectionName() throws {
        let data = try XCTUnwrap(swagger20.data(using: .utf8))
        let collection = try SwaggerImporter.parse(data: data)
        XCTAssertEqual(collection.name, "Pet Store")
    }

    func test_pathsGroupedByTag() throws {
        let data = try XCTUnwrap(swagger20.data(using: .utf8))
        let collection = try SwaggerImporter.parse(data: data)
        XCTAssertEqual(collection.items.count, 1)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder for 'pets' tag")
        }
        XCTAssertEqual(folder.name, "pets")
        XCTAssertEqual(folder.items.count, 3)
    }

    func test_baseURLComposed() throws {
        let data = try XCTUnwrap(swagger20.data(using: .utf8))
        let collection = try SwaggerImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0],
              case .request(let req) = folder.items[0] else { return XCTFail() }
        XCTAssertTrue(req.url.hasPrefix("https://petstore.example.com/api"))
    }

    func test_apiKeySecurityMapped() throws {
        let data = try XCTUnwrap(swagger20.data(using: .utf8))
        let collection = try SwaggerImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0] else { return XCTFail() }
        // Last item is /pets/{id} GET which has security
        let secureReq = folder.items.compactMap { item -> KoalaRequest? in
            guard case .request(let r) = item else { return nil }
            return r
        }.first(where: { $0.name == "Get Pet" })
        XCTAssertNotNil(secureReq)
        guard case .apiKey(let key, _, _) = secureReq?.auth else {
            return XCTFail("Expected apiKey auth")
        }
        XCTAssertEqual(key, "X-API-Key")
    }

    func test_swagger3x_throws_unsupportedVersion() {
        let swagger3 = """
        {
          "swagger": "3.0",
          "info": { "title": "Oops", "version": "1" },
          "paths": {}
        }
        """
        let data = swagger3.data(using: .utf8)!
        XCTAssertThrowsError(try SwaggerImporter.parse(data: data)) { error in
            guard case ImportError.unsupportedVersion = error else {
                return XCTFail("Expected unsupportedVersion")
            }
        }
    }
}
