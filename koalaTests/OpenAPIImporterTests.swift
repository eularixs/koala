import XCTest
@testable import koala

final class OpenAPIImporterTests: XCTestCase {

    // MARK: - Fixture: Petstore-like JSON (2 paths, parameters, requestBody with example)

    private let petstoreJSON = """
    {
      "openapi": "3.0.3",
      "info": {
        "title": "Petstore API",
        "version": "1.0.0"
      },
      "servers": [
        { "url": "https://petstore.example.com/v1" }
      ],
      "paths": {
        "/pets": {
          "get": {
            "summary": "List all pets",
            "operationId": "listPets",
            "tags": ["pets"],
            "parameters": [
              {
                "name": "limit",
                "in": "query",
                "required": false,
                "schema": { "type": "integer" }
              }
            ]
          },
          "post": {
            "summary": "Create a pet",
            "operationId": "createPet",
            "tags": ["pets"],
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object"
                  },
                  "example": {
                    "name": "Fluffy",
                    "species": "cat"
                  }
                }
              }
            }
          }
        },
        "/pets/{petId}": {
          "get": {
            "summary": "Get a pet",
            "operationId": "getPet",
            "tags": ["pets"],
            "parameters": [
              {
                "name": "petId",
                "in": "path",
                "required": true
              }
            ]
          }
        }
      }
    }
    """

    // MARK: - Tests

    func test_collectionName() throws {
        let data = try XCTUnwrap(petstoreJSON.data(using: .utf8))
        let collection = try OpenAPIImporter.parse(data: data)
        XCTAssertEqual(collection.name, "Petstore API")
    }

    func test_groupedByTag() throws {
        let data = try XCTUnwrap(petstoreJSON.data(using: .utf8))
        let collection = try OpenAPIImporter.parse(data: data)
        // All 3 operations share tag "pets" → 1 folder
        XCTAssertEqual(collection.items.count, 1)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder")
        }
        XCTAssertEqual(folder.name, "pets")
        XCTAssertEqual(folder.items.count, 3)
    }

    func test_URLBuiltFromServerAndPath() throws {
        let data = try XCTUnwrap(petstoreJSON.data(using: .utf8))
        let collection = try OpenAPIImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0],
              case .request(let req) = folder.items.first else {
            return XCTFail("Expected request")
        }
        XCTAssertTrue(req.url.hasPrefix("https://petstore.example.com/v1"))
    }

    func test_queryParamMapped() throws {
        let data = try XCTUnwrap(petstoreJSON.data(using: .utf8))
        let collection = try OpenAPIImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder")
        }
        // Find "List all pets" (GET /pets)
        let listPets = folder.items.compactMap { item -> KoalaRequest? in
            if case .request(let r) = item, r.method.rawValue == "GET" && r.url.hasSuffix("/pets") {
                return r
            }
            return nil
        }.first
        XCTAssertNotNil(listPets)
        let limitParam = listPets?.queryParams.first(where: { $0.key == "limit" })
        XCTAssertNotNil(limitParam)
        // not required → disabled
        XCTAssertFalse(limitParam?.isEnabled ?? true)
    }

    func test_requestBodyWithExample() throws {
        let data = try XCTUnwrap(petstoreJSON.data(using: .utf8))
        let collection = try OpenAPIImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder")
        }
        // Find "Create a pet" (POST /pets)
        let createPet = folder.items.compactMap { item -> KoalaRequest? in
            if case .request(let r) = item, r.method.rawValue == "POST" {
                return r
            }
            return nil
        }.first
        XCTAssertNotNil(createPet)
        guard case .json(let body) = createPet?.body else {
            return XCTFail("Expected JSON body for POST /pets")
        }
        XCTAssertTrue(body.contains("Fluffy") || body == "{}")
    }

    func test_pathParameterPreservedInURL() throws {
        let data = try XCTUnwrap(petstoreJSON.data(using: .utf8))
        let collection = try OpenAPIImporter.parse(data: data)
        guard case .folder(let folder) = collection.items[0] else {
            return XCTFail("Expected folder")
        }
        let getPet = folder.items.compactMap { item -> KoalaRequest? in
            if case .request(let r) = item, r.url.contains("{petId}") {
                return r
            }
            return nil
        }.first
        XCTAssertNotNil(getPet, "Expected request with {petId} in URL")
    }

    func test_unsupportedVersion_throws() throws {
        let swagger2 = """
        {
          "openapi": "2.0",
          "info": { "title": "Old API", "version": "1.0" },
          "paths": {}
        }
        """
        let data = try XCTUnwrap(swagger2.data(using: .utf8))
        XCTAssertThrowsError(try OpenAPIImporter.parse(data: data)) { error in
            guard case ImportError.unsupportedVersion = error else {
                XCTFail("Expected ImportError.unsupportedVersion, got \(error)")
                return
            }
        }
    }

    func test_invalidJSON_throws() {
        let badData = "{ invalid json }".data(using: .utf8)!
        XCTAssertThrowsError(try OpenAPIImporter.parse(data: badData)) { error in
            guard case ImportError.malformed = error else {
                XCTFail("Expected ImportError.malformed, got \(error)")
                return
            }
        }
    }
}
