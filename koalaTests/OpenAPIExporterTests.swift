import XCTest
@testable import koala

final class OpenAPIExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeCollection() -> KoalaCollection {
        let getReq = KoalaRequest(
            name: "List Items",
            method: .standard(.get),
            url: "https://api.example.com/items",
            queryParams: [KeyValuePair(key: "page", value: "1")],
            headers: [KeyValuePair(key: "Accept", value: "application/json")]
        )
        let postReq = KoalaRequest(
            name: "Create Item",
            method: .standard(.post),
            url: "https://api.example.com/items",
            body: .json("{\"name\": \"Widget\"}")
        )
        let folder = Folder(name: "Items", items: [.request(getReq), .request(postReq)])
        return KoalaCollection(name: "My API", items: [.folder(folder)])
    }

    // MARK: - Tests

    func test_producesValidJSON() throws {
        let data = try OpenAPIExporter.export(makeCollection())
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func test_requiredTopLevelFields() throws {
        let data = try OpenAPIExporter.export(makeCollection())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["openapi"])
        XCTAssertNotNil(json["info"])
        XCTAssertNotNil(json["paths"])
    }

    func test_openapiVersion_is3() throws {
        let data = try OpenAPIExporter.export(makeCollection())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let version = try XCTUnwrap(json["openapi"] as? String)
        XCTAssertTrue(version.hasPrefix("3."))
    }

    func test_pathsContainEntries() throws {
        let data = try OpenAPIExporter.export(makeCollection())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let paths = try XCTUnwrap(json["paths"] as? [String: Any])
        XCTAssertFalse(paths.isEmpty)
        XCTAssertNotNil(paths["/items"])
    }

    func test_infoTitle_matchesCollectionName() throws {
        let data = try OpenAPIExporter.export(makeCollection())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let info = try XCTUnwrap(json["info"] as? [String: Any])
        XCTAssertEqual(info["title"] as? String, "My API")
    }
}
