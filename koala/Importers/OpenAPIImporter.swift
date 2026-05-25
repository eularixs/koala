import Foundation

// NOTE: Only OpenAPI 3.x JSON is supported. YAML is not parsed.

// MARK: - OpenAPI DTOs

private struct OADocument: Decodable {
    let openapi: String
    let info: OAInfo
    let servers: [OAServer]?
    let paths: [String: OAPathItem]?
    let components: OAComponents?
}

private struct OAInfo: Decodable {
    let title: String
}

private struct OAServer: Decodable {
    let url: String
}

private struct OAComponents: Decodable {
    let securitySchemes: [String: OASecurityScheme]?
}

private struct OASecurityScheme: Decodable {
    let type: String
    let scheme: String?
    let name: String?
    let `in`: String?
}

private typealias OAPathItem = [String: OAOperation]

private struct OAOperation: Decodable {
    let operationId: String?
    let summary: String?
    let tags: [String]?
    let parameters: [OAParameter]?
    let requestBody: OARequestBody?
    let security: [[String: [String]]]?
}

private struct OAParameter: Decodable {
    let name: String
    let `in`: String
    let required: Bool?
    let schema: OASchema?
    let example: OAAnyCodable?
}

private struct OARequestBody: Decodable {
    let content: [String: OAMediaType]?
}

private struct OAMediaType: Decodable {
    let schema: OASchema?
    let example: OAAnyCodable?
    let examples: [String: OAExample]?
}

private struct OASchema: Decodable {
    let type: String?
    let properties: [String: OASchema]?
    let example: OAAnyCodable?
}

private struct OAExample: Decodable {
    let value: OAAnyCodable?
}

/// A type-erasing wrapper that decodes any JSON value and re-encodes as JSON string.
private struct OAAnyCodable: Decodable {
    let jsonString: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            jsonString = "\"\(str)\""
        } else if let num = try? container.decode(Double.self) {
            jsonString = String(num)
        } else if let bool = try? container.decode(Bool.self) {
            jsonString = bool ? "true" : "false"
        } else if let dict = try? container.decode([String: OAAnyCodable].self) {
            let pairs = dict.map { "\"\($0.key)\": \($0.value.jsonString)" }.joined(separator: ", ")
            jsonString = "{\(pairs)}"
        } else if let arr = try? container.decode([OAAnyCodable].self) {
            let elems = arr.map { $0.jsonString }.joined(separator: ", ")
            jsonString = "[\(elems)]"
        } else {
            jsonString = "null"
        }
    }
}

// MARK: - OpenAPIImporter

final class OpenAPIImporter {

    static func parse(data: Data) throws -> KoalaCollection {
        let decoder = JSONDecoder()
        let doc: OADocument
        do {
            doc = try decoder.decode(OADocument.self, from: data)
        } catch {
            throw ImportError.malformed("Could not decode OpenAPI JSON: \(error.localizedDescription)")
        }

        guard doc.openapi.hasPrefix("3.") else {
            throw ImportError.unsupportedVersion(doc.openapi)
        }

        let baseURL = doc.servers?.first?.url ?? ""
        let paths = doc.paths ?? [:]

        // Group requests by first tag → each tag becomes a Folder
        var tagFolders: [String: [KoalaRequest]] = [:]
        var untagged: [KoalaRequest] = []

        for (path, pathItem) in paths.sorted(by: { $0.key < $1.key }) {
            for (httpVerb, operation) in pathItem.sorted(by: { $0.key < $1.key }) {
                guard isValidHTTPVerb(httpVerb) else { continue }
                let request = buildRequest(
                    path: path,
                    verb: httpVerb,
                    operation: operation,
                    baseURL: baseURL
                )
                if let tag = operation.tags?.first {
                    tagFolders[tag, default: []].append(request)
                } else {
                    untagged.append(request)
                }
            }
        }

        var items: [CollectionItem] = tagFolders.sorted(by: { $0.key < $1.key }).map { tag, requests in
            let folderItems = requests.map { CollectionItem.request($0) }
            return CollectionItem.folder(Folder(name: tag, items: folderItems))
        }
        items += untagged.map { CollectionItem.request($0) }

        return KoalaCollection(name: doc.info.title, items: items)
    }

    // MARK: - Private helpers

    private static func isValidHTTPVerb(_ verb: String) -> Bool {
        let verbs = ["get", "post", "put", "patch", "delete", "head", "options", "trace"]
        return verbs.contains(verb.lowercased())
    }

    private static func buildRequest(
        path: String,
        verb: String,
        operation: OAOperation,
        baseURL: String
    ) -> KoalaRequest {
        let name = operation.summary ?? operation.operationId ?? "\(verb.uppercased()) \(path)"
        let url = baseURL + path  // path params remain as {paramName}
        let method = httpMethodValue(from: verb)

        var headers: [KeyValuePair] = []
        var queryParams: [KeyValuePair] = []

        for param in operation.parameters ?? [] {
            let enabled = param.required ?? false
            let pair = KeyValuePair(
                key: param.name,
                value: param.example?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "",
                isEnabled: enabled
            )
            switch param.in {
            case "query":  queryParams.append(pair)
            case "header": headers.append(pair)
            default: break
            }
        }

        let body = mapRequestBody(operation.requestBody)
        let auth = mapSecurity(operation.security)

        return KoalaRequest(
            name: name,
            method: method,
            url: url,
            queryParams: queryParams,
            headers: headers,
            auth: auth,
            body: body
        )
    }

    private static func mapRequestBody(_ rb: OARequestBody?) -> RequestBody {
        guard let rb = rb,
              let jsonMedia = rb.content?["application/json"] else { return .none }

        if let example = jsonMedia.example {
            return .json(example.jsonString)
        }
        if let exampleEntry = jsonMedia.examples?.values.first,
           let value = exampleEntry.value {
            return .json(value.jsonString)
        }
        if let schemaExample = jsonMedia.schema?.example {
            return .json(schemaExample.jsonString)
        }
        return .json("{}")
    }

    private static func mapSecurity(_ security: [[String: [String]]]?) -> AuthConfig {
        // TODO: Full OAuth2/complex security scheme resolution requires access to components.
        // Simple heuristics based on scheme key names only.
        guard let security = security, !security.isEmpty else { return .none }
        let key = security[0].keys.first?.lowercased() ?? ""
        if key.contains("bearer") || key.contains("jwt") {
            return .bearer(token: "")
        }
        if key.contains("basic") {
            return .basic(username: "", password: "")
        }
        if key.contains("apikey") || key.contains("api_key") {
            return .apiKey(key: "X-API-Key", value: "", location: .header)
        }
        return .none
    }

    private static func httpMethodValue(from verb: String) -> HTTPMethodValue {
        let upper = verb.uppercased()
        if let m = HTTPMethod(rawValue: upper) { return .standard(m) }
        return .custom(upper)
    }
}
