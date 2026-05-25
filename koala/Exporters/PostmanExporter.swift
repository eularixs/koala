import Foundation

// MARK: - Postman v2.1 output DTOs

private struct PMOutCollection: Encodable {
    let info: PMOutInfo
    let item: [PMOutItem]
    let auth: PMOutAuth?
    let variable: [PMOutVariable]?
}

private struct PMOutInfo: Encodable {
    let name: String
    let schema: String = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
    let version: String = "2.1.0"
}

private struct PMOutItem: Encodable {
    let name: String
    let item: [PMOutItem]?       // non-nil → folder
    let request: PMOutRequest?   // non-nil → request
}

private struct PMOutRequest: Encodable {
    let method: String
    let header: [PMOutHeader]
    let url: PMOutUrl
    let auth: PMOutAuth?
    let body: PMOutBody?
}

private struct PMOutHeader: Encodable {
    let key: String
    let value: String
    let disabled: Bool?
}

private struct PMOutUrl: Encodable {
    let raw: String
    let query: [PMOutQuery]?
}

private struct PMOutQuery: Encodable {
    let key: String
    let value: String
    let disabled: Bool?
}

private struct PMOutBody: Encodable {
    let mode: String
    let raw: String?
    let urlencoded: [PMOutFormParam]?
    let formdata: [PMOutFormParam]?
    let graphql: PMOutGraphQL?
    let options: PMOutBodyOptions?
}

private struct PMOutFormParam: Encodable {
    let key: String
    let value: String
    let disabled: Bool?
}

private struct PMOutGraphQL: Encodable {
    let query: String
    let variables: String
}

private struct PMOutBodyOptions: Encodable {
    let raw: PMOutRawOptions?
}

private struct PMOutRawOptions: Encodable {
    let language: String
}

private struct PMOutAuth: Encodable {
    let type: String
    let bearer: [PMOutAuthParam]?
    let basic: [PMOutAuthParam]?
    let apikey: [PMOutAuthParam]?
    let oauth2: [PMOutAuthParam]?
}

private struct PMOutAuthParam: Encodable {
    let key: String
    let value: String
    let type: String = "string"
}

private struct PMOutVariable: Encodable {
    let key: String
    let value: String
}

// MARK: - PostmanExporter

final class PostmanExporter {

    static func export(_ collection: KoalaCollection) throws -> Data {
        let pmCollection = PMOutCollection(
            info: PMOutInfo(name: collection.name),
            item: collection.items.map(mapItem),
            auth: mapAuth(collection.auth),
            variable: collection.variables.isEmpty ? nil :
                collection.variables.map { PMOutVariable(key: $0.key, value: $0.value) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(pmCollection)
    }

    // MARK: - Mapping helpers

    private static func mapItem(_ item: CollectionItem) -> PMOutItem {
        switch item {
        case .folder(let folder):
            return PMOutItem(name: folder.name, item: folder.items.map(mapItem), request: nil)
        case .request(let req):
            return PMOutItem(name: req.name, item: nil, request: mapRequest(req))
        }
    }

    private static func mapRequest(_ req: KoalaRequest) -> PMOutRequest {
        let headers = req.headers.map { h in
            PMOutHeader(key: h.key, value: h.value, disabled: h.isEnabled ? nil : true)
        }
        let query = req.queryParams.isEmpty ? nil : req.queryParams.map { q in
            PMOutQuery(key: q.key, value: q.value, disabled: q.isEnabled ? nil : true)
        }
        let url = PMOutUrl(raw: req.url, query: query)
        return PMOutRequest(
            method: req.method.rawValue,
            header: headers,
            url: url,
            auth: mapAuth(req.auth),
            body: mapBody(req.body)
        )
    }

    private static func mapAuth(_ auth: AuthConfig?) -> PMOutAuth? {
        guard let auth = auth else { return nil }
        switch auth {
        case .none:
            return PMOutAuth(type: "noauth", bearer: nil, basic: nil, apikey: nil, oauth2: nil)
        case .bearer(let token):
            return PMOutAuth(type: "bearer",
                             bearer: [PMOutAuthParam(key: "token", value: token)],
                             basic: nil, apikey: nil, oauth2: nil)
        case .basic(let u, let p):
            return PMOutAuth(type: "basic", bearer: nil,
                             basic: [PMOutAuthParam(key: "username", value: u),
                                     PMOutAuthParam(key: "password", value: p)],
                             apikey: nil, oauth2: nil)
        case .apiKey(let key, let value, let loc):
            return PMOutAuth(type: "apikey", bearer: nil, basic: nil,
                             apikey: [PMOutAuthParam(key: "key", value: key),
                                      PMOutAuthParam(key: "value", value: value),
                                      PMOutAuthParam(key: "in", value: loc.rawValue)],
                             oauth2: nil)
        case .oauth2:
            return PMOutAuth(type: "oauth2", bearer: nil, basic: nil, apikey: nil, oauth2: [])
        case .awsSignature:
            return nil  // no direct Postman representation; skip
        }
    }

    private static func mapBody(_ body: RequestBody) -> PMOutBody? {
        switch body {
        case .none:
            return nil
        case .json(let content):
            return PMOutBody(mode: "raw", raw: content, urlencoded: nil, formdata: nil, graphql: nil,
                             options: PMOutBodyOptions(raw: PMOutRawOptions(language: "json")))
        case .raw(let content, _):
            return PMOutBody(mode: "raw", raw: content, urlencoded: nil, formdata: nil, graphql: nil,
                             options: PMOutBodyOptions(raw: PMOutRawOptions(language: "text")))
        case .formURLEncoded(let pairs):
            let params = pairs.map { PMOutFormParam(key: $0.key, value: $0.value, disabled: $0.isEnabled ? nil : true) }
            return PMOutBody(mode: "urlencoded", raw: nil, urlencoded: params, formdata: nil, graphql: nil, options: nil)
        case .multipart(let items):
            let params = items.map { PMOutFormParam(key: $0.key, value: $0.value, disabled: $0.isEnabled ? nil : true) }
            return PMOutBody(mode: "formdata", raw: nil, urlencoded: nil, formdata: params, graphql: nil, options: nil)
        case .graphql(let query, let variables):
            return PMOutBody(mode: "graphql", raw: nil, urlencoded: nil, formdata: nil,
                             graphql: PMOutGraphQL(query: query, variables: variables), options: nil)
        case .binary:
            return PMOutBody(mode: "binary", raw: nil, urlencoded: nil, formdata: nil, graphql: nil, options: nil)
        }
    }
}
