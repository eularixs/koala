import Foundation

// MARK: - OpenAPI 3.0 output model (dictionary-based for flexible JSON)

final class OpenAPIExporter {

    static func export(_ collection: KoalaCollection) throws -> Data {
        var doc: [String: Any] = [
            "openapi": "3.0.0",
            "info": ["title": collection.name, "version": "1.0.0"],
            "paths": buildPaths(collection.items)
        ]
        let servers = buildServers(collection)
        if !servers.isEmpty { doc["servers"] = servers }

        let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        return data
    }

    // MARK: - Private helpers

    private static func buildPaths(_ items: [CollectionItem]) -> [String: Any] {
        var paths: [String: Any] = [:]
        collectRequests(items: items, tag: nil, into: &paths)
        return paths
    }

    private static func collectRequests(items: [CollectionItem], tag: String?, into paths: inout [String: Any]) {
        for item in items {
            switch item {
            case .folder(let folder):
                collectRequests(items: folder.items, tag: folder.name, into: &paths)
            case .request(let req):
                let path = urlPath(req.url)
                let verb = req.method.rawValue.lowercased()
                var operation: [String: Any] = [:]
                if let tag = tag { operation["tags"] = [tag] }
                operation["summary"] = req.name
                let params = buildParameters(req)
                if !params.isEmpty { operation["parameters"] = params }
                if let rb = buildRequestBody(req.body) { operation["requestBody"] = rb }
                operation["responses"] = ["200": ["description": "OK"]]
                var pathItem = paths[path] as? [String: Any] ?? [:]
                pathItem[verb] = operation
                paths[path] = pathItem
            }
        }
    }

    private static func buildParameters(_ req: KoalaRequest) -> [[String: Any]] {
        var params: [[String: Any]] = []
        for q in req.queryParams where q.isEnabled {
            params.append(["name": q.key, "in": "query",
                           "schema": ["type": "string"],
                           "example": q.value])
        }
        for h in req.headers where h.isEnabled {
            params.append(["name": h.key, "in": "header",
                           "schema": ["type": "string"],
                           "example": h.value])
        }
        return params
    }

    private static func buildRequestBody(_ body: RequestBody) -> [String: Any]? {
        switch body {
        case .none: return nil
        case .json(let content):
            return ["content": ["application/json": ["example": parseJSON(content) ?? content]]]
        case .formURLEncoded(let pairs):
            let schema: [String: Any] = [
                "type": "object",
                "properties": Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, ["type": "string"] as Any) })
            ]
            return ["content": ["application/x-www-form-urlencoded": ["schema": schema]]]
        case .multipart(let items):
            let schema: [String: Any] = [
                "type": "object",
                "properties": Dictionary(uniqueKeysWithValues: items.map { ($0.key, ["type": "string"] as Any) })
            ]
            return ["content": ["multipart/form-data": ["schema": schema]]]
        case .raw(let content, let ct):
            return ["content": [ct.isEmpty ? "text/plain" : ct: ["example": content]]]
        case .graphql(let query, _):
            return ["content": ["application/json": ["example": ["query": query]]]]
        case .binary:
            return ["content": ["application/octet-stream": ["schema": ["type": "string", "format": "binary"]]]]
        }
    }

    private static func buildServers(_ collection: KoalaCollection) -> [[String: String]] {
        // Extract unique base URLs from top-level requests
        var seen = Set<String>()
        var servers: [[String: String]] = []
        for item in collection.items {
            if case .request(let req) = item, let base = extractBase(req.url), !base.isEmpty {
                if seen.insert(base).inserted { servers.append(["url": base]) }
            }
        }
        return servers
    }

    private static func urlPath(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL) else { return rawURL }
        let path = url.path
        return path.isEmpty ? "/" : path
    }

    private static func extractBase(_ rawURL: String) -> String? {
        guard let url = URL(string: rawURL),
              let scheme = url.scheme, let host = url.host else { return nil }
        return "\(scheme)://\(host)"
    }

    private static func parseJSON(_ string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
