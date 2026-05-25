import XCTest
@testable import koala

final class InsomniaImporterTests: XCTestCase {

    // MARK: - Fixtures

    private let validExport = """
    {
      "_type": "export",
      "__export_format": 4,
      "resources": [
        {
          "_id": "wrk_001",
          "_type": "workspace",
          "parentId": null,
          "name": "My API"
        },
        {
          "_id": "grp_001",
          "_type": "request_group",
          "parentId": "wrk_001",
          "name": "Users"
        },
        {
          "_id": "req_001",
          "_type": "request",
          "parentId": "grp_001",
          "name": "List Users",
          "method": "GET",
          "url": "https://api.example.com/users",
          "headers": [
            { "name": "Accept", "value": "application/json" }
          ],
          "parameters": [
            { "name": "page", "value": "1" }
          ],
          "authentication": {
            "type": "bearer",
            "token": "mytoken123"
          }
        },
        {
          "_id": "req_002",
          "_type": "request",
          "parentId": "grp_001",
          "name": "Create User",
          "method": "POST",
          "url": "https://api.example.com/users",
          "headers": [],
          "body": {
            "mimeType": "application/json",
            "text": "{\\"name\\": \\"Bob\\"}"
          },
          "authentication": {
            "type": "basic",
            "username": "admin",
            "password": "secret"
          }
        },
        {
          "_id": "req_003",
          "_type": "request",
          "parentId": "wrk_001",
          "name": "Top Level",
          "method": "DELETE",
          "url": "https://api.example.com/resource/1",
          "headers": []
        }
      ]
    }
    """

    // MARK: - Tests

    func test_returnsOneCollectionPerWorkspace() throws {
        let data = try XCTUnwrap(validExport.data(using: .utf8))
        let collections = try InsomniaImporter.parse(data: data)
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections[0].name, "My API")
    }

    func test_requestGroupMappedToFolder() throws {
        let data = try XCTUnwrap(validExport.data(using: .utf8))
        let collection = try InsomniaImporter.parse(data: data)[0]
        let folderItem = collection.items.first(where: {
            if case .folder(let f) = $0 { return f.name == "Users" }
            return false
        })
        XCTAssertNotNil(folderItem)
    }

    func test_requestInsideFolderMapped() throws {
        let data = try XCTUnwrap(validExport.data(using: .utf8))
        let collection = try InsomniaImporter.parse(data: data)[0]
        guard case .folder(let folder) = collection.items.first(where: { if case .folder = $0 { return true }; return false }) else {
            return XCTFail("Expected folder")
        }
        XCTAssertEqual(folder.items.count, 2)
        guard case .request(let req) = folder.items[0] else { return XCTFail("Expected request") }
        XCTAssertEqual(req.name, "List Users")
        XCTAssertEqual(req.method.rawValue, "GET")
        XCTAssertEqual(req.queryParams.count, 1)
        XCTAssertEqual(req.queryParams[0].key, "page")
        guard case .bearer(let token) = req.auth else { return XCTFail("Expected bearer") }
        XCTAssertEqual(token, "mytoken123")
    }

    func test_jsonBodyMapped() throws {
        let data = try XCTUnwrap(validExport.data(using: .utf8))
        let collection = try InsomniaImporter.parse(data: data)[0]
        guard case .folder(let folder) = collection.items.first(where: { if case .folder = $0 { return true }; return false }),
              case .request(let req) = folder.items[1] else { return XCTFail("Expected POST req") }
        guard case .json(let body) = req.body else { return XCTFail("Expected JSON body") }
        XCTAssertTrue(body.contains("Bob"))
    }

    func test_invalidType_throws() {
        let bad = """
        { "_type": "something_else", "resources": [] }
        """
        let data = bad.data(using: .utf8)!
        XCTAssertThrowsError(try InsomniaImporter.parse(data: data)) { error in
            guard case ImportError.malformed = error else {
                return XCTFail("Expected ImportError.malformed")
            }
        }
    }
}
