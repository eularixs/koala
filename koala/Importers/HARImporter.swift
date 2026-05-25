import Foundation

// MARK: - HAR DTOs

private struct HARFile: Decodable {
    let log: HARLog
}

private struct HARLog: Decodable {
    let creator: HARCreator?
    let entries: [HAREntry]
}

private struct HARCreator: Decodable {
    let name: String?
}

private struct HAREntry: Decodable {
    let request: HARRequest
}

private struct HARRequest: Decodable {
    let method: String
    let url: String
    let headers: [HARHeader]
    let queryString: [HARQueryParam]?
    let postData: HARPostData?
}

private struct HARHeader: Decodable {
    let name: String
    let value: String
}

private struct HARQueryParam: Decodable {
    let name: String
    let value: String
}

private struct HARPostData: Decodable {
    let mimeType: String?
    let text: String?
    let params: [HARParam]?
}

private struct HARParam: Decodable {
    let name: String
    let value: String?
}

// MARK: - HARImporter

final class HARImporter {

    static func parse(data: Data) throws -> KoalaCollection {
        let decoder = JSONDecoder()
        let har: HARFile
        do {
            har = try decoder.decode(HARFile.self, from: data)
        } catch {
            throw ImportError.malformed("Could not decode HAR JSON: \(error.localizedDescription)")
        }

        let collectionName = har.log.creator?.name ?? "HAR Import"
        let items: [CollectionItem] = har.log.entries.map { entry in
            .request(buildRequest(entry.request))
        }
        return KoalaCollection(name: collectionName, items: items)
    }

    // MARK: - Private helpers

    private static func buildRequest(_ har: HARRequest) -> KoalaRequest {
        let method = methodValue(har.method)
        let queryParams = (har.queryString ?? []).map { p in
            KeyValuePair(key: p.name, value: p.value)
        }
        let (headers, auth) = mapHeaders(har.headers)
        let body = mapBody(har.postData)
        let name = "\(har.method) \(cleanPath(har.url))"
        return KoalaRequest(
            name: name,
            method: method,
            url: har.url,
            queryParams: queryParams,
            headers: headers,
            auth: auth,
            body: body
        )
    }

    private static func mapHeaders(_ harHeaders: [HARHeader]) -> ([KeyValuePair], AuthConfig) {
        var auth: AuthConfig = .none
        var headers: [KeyValuePair] = []

        for h in harHeaders {
            if h.name.lowercased() == "authorization" {
                auth = parseAuthHeader(h.value)
                // Do not add to headers if we extracted auth from it
                continue
            }
            headers.append(KeyValuePair(key: h.name, value: h.value))
        }
        return (headers, auth)
    }

    private static func parseAuthHeader(_ value: String) -> AuthConfig {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("bearer ") {
            let token = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            return .bearer(token: token)
        }
        if trimmed.lowercased().hasPrefix("basic ") {
            let encoded = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if let decoded = Data(base64Encoded: encoded),
               let str = String(data: decoded, encoding: .utf8) {
                let parts = str.split(separator: ":", maxSplits: 1)
                let username = parts.count > 0 ? String(parts[0]) : ""
                let password = parts.count > 1 ? String(parts[1]) : ""
                return .basic(username: username, password: password)
            }
            return .basic(username: "", password: "")
        }
        return .none
    }

    private static func mapBody(_ postData: HARPostData?) -> RequestBody {
        guard let postData = postData else { return .none }
        let mime = postData.mimeType ?? ""
        if mime.contains("application/json") {
            return .json(postData.text ?? "{}")
        }
        if mime.contains("application/x-www-form-urlencoded") {
            if let params = postData.params {
                let pairs = params.map { KeyValuePair(key: $0.name, value: $0.value ?? "") }
                return .formURLEncoded(pairs)
            }
            // Fall through to parse text
            let text = postData.text ?? ""
            let pairs = text.split(separator: "&").map { part -> KeyValuePair in
                let kv = part.split(separator: "=", maxSplits: 1)
                let k = kv.count > 0 ? String(kv[0]) : ""
                let v = kv.count > 1 ? String(kv[1]) : ""
                return KeyValuePair(key: k, value: v)
            }
            return .formURLEncoded(pairs)
        }
        if let text = postData.text, !text.isEmpty {
            return .raw(content: text, contentType: mime.isEmpty ? "text/plain" : mime)
        }
        return .none
    }

    private static func cleanPath(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.path.isEmpty ? "/" : parsed.path
    }

    private static func methodValue(_ raw: String) -> HTTPMethodValue {
        let upper = raw.uppercased()
        if let m = HTTPMethod(rawValue: upper) { return .standard(m) }
        return .custom(upper)
    }
}
