import Foundation

// MARK: - Apidog Native DTOs

private struct ADNativeCollection: Decodable {
    let apidoc: ADApidoc
}

private struct ADApidoc: Decodable {
    let name: String?
    let endpoints: [ADEndpoint]?
    let folders: [ADFolder]?
}

private struct ADEndpoint: Decodable {
    let name: String?
    let method: String?
    let path: String?
    let folderId: String?
    let headers: [ADKeyValue]?
    let queryParams: [ADKeyValue]?
    let requestBody: ADRequestBody?
}

private struct ADFolder: Decodable {
    let id: String
    let name: String
}

private struct ADKeyValue: Decodable {
    let name: String
    let value: String?
    let description: String?
}

private struct ADRequestBody: Decodable {
    let type: String?
    let jsonBody: String?
    let formBody: [ADKeyValue]?
}

// MARK: - OpenAPI 3 with x-apidog extensions DTOs

private struct ADOpenAPIDoc: Decodable {
    let openapi: String
    let info: ADInfo
    let servers: [ADServer]?
    let paths: [String: ADPathItem]?
    let xApidogFolders: [ADApidogFolder]?

    enum CodingKeys: String, CodingKey {
        case openapi, info, servers, paths
        case xApidogFolders = "x-apidog-folders"
    }
}

private struct ADInfo: Decodable { let title: String }
private struct ADServer: Decodable { let url: String }
private typealias ADPathItem = [String: ADOperation]

private struct ADOperation: Decodable {
    let operationId: String?
    let summary: String?
    let tags: [String]?
    let parameters: [ADParameter]?
    let requestBody: ADOARequestBody?
    let xApidogFolder: String?

    enum CodingKeys: String, CodingKey {
        case operationId, summary, tags, parameters, requestBody
        case xApidogFolder = "x-apidog-folder"
    }
}

private struct ADParameter: Decodable {
    let name: String
    let `in`: String
    let required: Bool?
    let example: ADAnyCodable?
}

private struct ADOARequestBody: Decodable {
    let content: [String: ADMediaType]?
}

private struct ADMediaType: Decodable {
    let example: ADAnyCodable?
}

private struct ADApidogFolder: Decodable {
    let id: String?
    let name: String
}

private struct ADAnyCodable: Decodable {
    let jsonString: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { jsonString = "\"\(s)\""; return }
        if let n = try? c.decode(Double.self) { jsonString = String(n); return }
        if let b = try? c.decode(Bool.self) { jsonString = b ? "true" : "false"; return }
        if let d = try? c.decode([String: ADAnyCodable].self) {
            let pairs = d.map { "\"\($0.key)\": \($0.value.jsonString)" }.joined(separator: ", ")
            jsonString = "{\(pairs)}"; return
        }
        if let a = try? c.decode([ADAnyCodable].self) {
            jsonString = "[\(a.map { $0.jsonString }.joined(separator: ", "))]"; return
        }
        jsonString = "null"
    }
}

// MARK: - ApidogImporter

final class ApidogImporter {

    static func parse(data: Data) throws -> KoalaCollection {
        let decoder = JSONDecoder()

        // Try OpenAPI-flavored export first
        if let doc = try? decoder.decode(ADOpenAPIDoc.self, from: data) {
            guard doc.openapi.hasPrefix("3.") else {
                throw ImportError.unsupportedVersion(doc.openapi)
            }
            return parseOpenAPIFlavored(doc)
        }

        // Try native Apidog shape
        if let native = try? decoder.decode(ADNativeCollection.self, from: data) {
            return parseNative(native)
        }

        throw ImportError.unsupportedVersion("Unrecognized Apidog export shape")
    }

    // MARK: - OpenAPI-flavored

    private static func parseOpenAPIFlavored(_ doc: ADOpenAPIDoc) -> KoalaCollection {
        let baseURL = doc.servers?.first?.url ?? ""
        var tagFolders: [String: [KoalaRequest]] = [:]
        var untagged: [KoalaRequest] = []

        for (path, pathItem) in (doc.paths ?? [:]).sorted(by: { $0.key < $1.key }) {
            for (verb, op) in pathItem.sorted(by: { $0.key < $1.key }) {
                guard isHTTPVerb(verb) else { continue }
                let req = buildOARequest(path: path, verb: verb, op: op, baseURL: baseURL)
                let tag = op.xApidogFolder ?? op.tags?.first
                if let tag = tag {
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

    private static func buildOARequest(path: String, verb: String, op: ADOperation, baseURL: String) -> KoalaRequest {
        let name = op.summary ?? op.operationId ?? "\(verb.uppercased()) \(path)"
        var headers: [KeyValuePair] = []
        var queryParams: [KeyValuePair] = []

        for param in op.parameters ?? [] {
            let pair = KeyValuePair(
                key: param.name,
                value: param.example?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "",
                isEnabled: param.required ?? false
            )
            switch param.in {
            case "query":  queryParams.append(pair)
            case "header": headers.append(pair)
            default: break
            }
        }

        let body: RequestBody
        if let content = op.requestBody?.content,
           let media = content["application/json"] {
            body = .json(media.example?.jsonString ?? "{}")
        } else {
            body = .none
        }

        let method: HTTPMethodValue = {
            let u = verb.uppercased()
            if let m = HTTPMethod(rawValue: u) { return .standard(m) }
            return .custom(u)
        }()

        return KoalaRequest(name: name, method: method, url: baseURL + path,
                            queryParams: queryParams, headers: headers, body: body)
    }

    // MARK: - Native Apidog

    private static func parseNative(_ native: ADNativeCollection) -> KoalaCollection {
        let name = native.apidoc.name ?? "Apidog Import"
        let folderMap: [String: String] = Dictionary(
            uniqueKeysWithValues: (native.apidoc.folders ?? []).map { ($0.id, $0.name) }
        )
        var folderItems: [String: [CollectionItem]] = [:]
        var unassigned: [CollectionItem] = []

        for ep in native.apidoc.endpoints ?? [] {
            let req = buildNativeRequest(ep)
            if let fid = ep.folderId, let _ = folderMap[fid] {
                folderItems[fid, default: []].append(.request(req))
            } else {
                unassigned.append(.request(req))
            }
        }

        var items: [CollectionItem] = (native.apidoc.folders ?? []).map { f in
            .folder(Folder(name: f.name, items: folderItems[f.id] ?? []))
        }
        items += unassigned
        return KoalaCollection(name: name, items: items)
    }

    private static func buildNativeRequest(_ ep: ADEndpoint) -> KoalaRequest {
        let method: HTTPMethodValue = {
            let u = (ep.method ?? "GET").uppercased()
            if let m = HTTPMethod(rawValue: u) { return .standard(m) }
            return .custom(u)
        }()
        let headers = (ep.headers ?? []).map { KeyValuePair(key: $0.name, value: $0.value ?? "") }
        let queryParams = (ep.queryParams ?? []).map { KeyValuePair(key: $0.name, value: $0.value ?? "") }
        let body: RequestBody = {
            guard let rb = ep.requestBody else { return .none }
            switch rb.type {
            case "json":   return .json(rb.jsonBody ?? "{}")
            case "form":
                let pairs = (rb.formBody ?? []).map { KeyValuePair(key: $0.name, value: $0.value ?? "") }
                return .formURLEncoded(pairs)
            default: return .none
            }
        }()
        return KoalaRequest(name: ep.name ?? "Request", method: method, url: ep.path ?? "",
                            queryParams: queryParams, headers: headers, body: body)
    }

    private static func isHTTPVerb(_ v: String) -> Bool {
        ["get", "post", "put", "patch", "delete", "head", "options", "trace"].contains(v.lowercased())
    }
}
