import XCTest
@testable import koala

final class PostmanExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeCollection() -> KoalaCollection {
        let getReq = KoalaRequest(
            name: "Get Users",
            method: .standard(.get),
            url: "https://api.example.com/users",
            queryParams: [KeyValuePair(key: "page", value: "1")],
            headers: [KeyValuePair(key: "Accept", value: "application/json")],
            auth: .bearer(token: "tok123")
        )
        let postReq = KoalaRequest(
            name: "Create User",
            method: .standard(.post),
            url: "https://api.example.com/users",
            headers: [KeyValuePair(key: "Content-Type", value: "application/json")],
            body: .json("{\"name\": \"Alice\"}")
        )
        let folder = Folder(name: "Users", items: [.request(getReq), .request(postReq)])
        return KoalaCollection(name: "Test API", items: [.folder(folder)])
    }

    // MARK: - Tests

    func test_exportProducesValidJSON() throws {
        let data = try PostmanExporter.export(makeCollection())
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func test_schemaVersion_isV21() throws {
        let data = try PostmanExporter.export(makeCollection())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let info = try XCTUnwrap(json["info"] as? [String: Any])
        let schema = try XCTUnwrap(info["schema"] as? String)
        XCTAssertTrue(schema.contains("v2.1"))
    }

    func test_roundTrip_collectionName() throws {
        let original = makeCollection()
        let exported = try PostmanExporter.export(original)
        let reimported = try PostmanImporter.parse(data: exported)
        XCTAssertEqual(reimported.name, original.name)
    }

    func test_roundTrip_folderAndRequestCount() throws {
        let original = makeCollection()
        let exported = try PostmanExporter.export(original)
        let reimported = try PostmanImporter.parse(data: exported)
        XCTAssertEqual(reimported.items.count, 1)
        guard case .folder(let folder) = reimported.items[0] else {
            return XCTFail("Expected folder after round-trip")
        }
        XCTAssertEqual(folder.name, "Users")
        XCTAssertEqual(folder.items.count, 2)
    }

    func test_roundTrip_bearerAuth() throws {
        let original = makeCollection()
        let exported = try PostmanExporter.export(original)
        let reimported = try PostmanImporter.parse(data: exported)
        guard case .folder(let folder) = reimported.items[0],
              case .request(let req) = folder.items[0] else { return XCTFail() }
        guard case .bearer(let token) = req.auth else {
            return XCTFail("Expected bearer after round-trip")
        }
        XCTAssertEqual(token, "tok123")
    }
}
