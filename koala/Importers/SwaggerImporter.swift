import Foundation

// MARK: - Swagger 2.0 DTOs

private struct SW2Document: Decodable {
    let swagger: String
    let info: SW2Info
    let host: String?
    let basePath: String?
    let schemes: [String]?
    let paths: [String: SW2PathItem]?
    let securityDefinitions: [String: SW2SecurityDef]?
}

private struct SW2Info: Decodable {
    let title: String
}

private typealias SW2PathItem = [String: SW2Operation]

private struct SW2Operation: Decodable {
    let operationId: String?
    let summary: String?
    let tags: [String]?
    let parameters: [SW2Parameter]?
    let security: [[String: [String]]]?
    let consumes: [String]?
}

private struct SW2Parameter: Decodable {
    let name: String
    let `in`: String
    let required: Bool?
    let description: String?
    let schema: SW2Schema?
}

private struct SW2Schema: Decodable {
    let example: SW2AnyCodable?
}

private struct SW2SecurityDef: Decodable {
    let type: String
    let name: String?
    let `in`: String?
    let flow: String?
    let authorizationUrl: String?
    let tokenUrl: String?
}

private struct SW2AnyCodable: Decodable {
    let jsonString: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { jsonString = "\"\(s)\""; return }
        if let n = try? c.decode(Double.self) { jsonString = String(n); return }
        if let b = try? c.decode(Bool.self) { jsonString = b ? "true" : "false"; return }
        if let d = try? c.decode([String: SW2AnyCodable].self) {
            let pairs = d.map { "\"\($0.key)\": \($0.value.jsonString)" }.joined(separator: ", ")
            jsonString = "{\(pairs)}"; return
        }
        if let a = try? c.decode([SW2AnyCodable].self) {
            jsonString = "[\(a.map { $0.jsonString }.joined(separator: ", "))]"; return
        }
        jsonString = "null"
    }
}

// MARK: - SwaggerImporter

final class SwaggerImporter {

    static func parse(data: Data) throws -> KoalaCollection {
        let decoder = JSONDecoder()
        let doc: SW2Document
        do {
            doc = try decoder.decode(SW2Document.self, from: data)
        } catch {
            throw ImportError.malformed("Could not decode Swagger JSON: \(error.localizedDescription)")
        }

        if doc.swagger.hasPrefix("3.") {
            throw ImportError.unsupportedVersion(
                "\(doc.swagger) — use OpenAPIImporter for OpenAPI 3.x"
            )
        }
        guard doc.swagger == "2.0" else {
            throw ImportError.unsupportedVersion(doc.swagger)
        }

        let baseURL = buildBaseURL(doc)
        var tagFolders: [String: [KoalaRequest]] = [:]
        var untagged: [KoalaRequest] = []

        for (path, pathItem) in (doc.paths ?? [:]).sorted(by: { $0.key < $1.key }) {
            for (verb, op) in pathItem.sorted(by: { $0.key < $1.key }) {
                guard isHTTPVerb(verb) else { continue }
                let req = buildRequest(path: path, verb: verb, op: op,
                                       baseURL: baseURL, secDefs: doc.securityDefinitions)
                if let tag = op.tags?.first {
                    tagFolders[tag, default: []].append(req)
                } else {
                    untagged.append(req)
                }
            }
        }

        var items: [CollectionItem] = tagFolders.sorted(by: { $0.key < $1.key }).map { tag, reqs in
            .folder(Folder(name: tag, items: reqs.map { .request($0) }))
        }
        items += untagged.map { .request($0) }
        return KoalaCollection(name: doc.info.title, items: items)
    }

    // MARK: - Private helpers

    private static func buildBaseURL(_ doc: SW2Document) -> String {
        let scheme = doc.schemes?.first ?? "https"
        let host = doc.host ?? ""
        let base = doc.basePath ?? ""
        guard !host.isEmpty else { return base }
        return "\(scheme)://\(host)\(base)"
    }

    private static func buildRequest(
        path: String, verb: String, op: SW2Operation,
        baseURL: String, secDefs: [String: SW2SecurityDef]?
    ) -> KoalaRequest {
        let name = op.summary ?? op.operationId ?? "\(verb.uppercased()) \(path)"
        let url = baseURL + path
        let method: HTTPMethodValue = {
            let u = verb.uppercased()
            if let m = HTTPMethod(rawValue: u) { return .standard(m) }
            return .custom(u)
        }()

        var headers: [KeyValuePair] = []
        var queryParams: [KeyValuePair] = []
        var body: RequestBody = .none

        for param in op.parameters ?? [] {
            switch param.in {
            case "query":
                queryParams.append(KeyValuePair(key: param.name, value: "",
                                                description: param.description ?? "",
                                                isEnabled: param.required ?? false))
            case "header":
                headers.append(KeyValuePair(key: param.name, value: "",
                                            description: param.description ?? "",
                                            isEnabled: param.required ?? false))
            case "body":
                let example = param.schema?.example?.jsonString ?? "{}"
                body = .json(example)
            default: break
            }
        }

        let auth = mapSecurity(op.security, secDefs: secDefs)
        return KoalaRequest(name: name, method: method, url: url,
                            queryParams: queryParams, headers: headers, auth: auth, body: body)
    }

    private static func mapSecurity(
        _ security: [[String: [String]]]?,
        secDefs: [String: SW2SecurityDef]?
    ) -> AuthConfig {
        guard let security = security, !security.isEmpty,
              let key = security[0].keys.first,
              let def = secDefs?[key] else { return .none }
        switch def.type.lowercased() {
        case "apikey":
            let loc: APIKeyLocation = (def.in == "query") ? .query : .header
            return .apiKey(key: def.name ?? "X-API-Key", value: "", location: loc)
        case "basic":
            return .basic(username: "", password: "")
        case "oauth2":
            return .bearer(token: "")   // placeholder — full OAuth2 config not possible from spec alone
        default:
            return .none
        }
    }

    private static func isHTTPVerb(_ v: String) -> Bool {
        ["get", "post", "put", "patch", "delete", "head", "options", "trace"].contains(v.lowercased())
    }
}
