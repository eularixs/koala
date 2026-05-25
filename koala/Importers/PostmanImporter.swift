import Foundation

// MARK: - Postman v2.1 DTOs

private struct PMCollection: Decodable {
    let info: PMInfo
    let item: [PMItem]
    let auth: PMAuth?
}

private struct PMInfo: Decodable {
    let name: String
    let schema: String
}

// PMItem represents either a folder (has `item` child array) or a request (has `request` key)
private struct PMItem: Decodable {
    let name: String
    let item: [PMItem]?
    let request: PMRequest?
    let auth: PMAuth?
}

private struct PMRequest: Decodable {
    let method: String?
    let header: [PMHeader]?
    let url: PMUrl?
    let auth: PMAuth?
    let body: PMBody?
}

private struct PMHeader: Decodable {
    let key: String
    let value: String
    let disabled: Bool?
}

// PMUrl can be a plain string or an object — handled via custom init
private struct PMUrl: Decodable {
    let raw: String
    let query: [PMQueryParam]?

    init(from decoder: Decoder) throws {
        if let str = try? decoder.singleValueContainer().decode(String.self) {
            raw = str
            query = nil
            return
        }
        let container = try decoder.container(keyedBy: PMUrlKeys.self)
        raw = (try? container.decode(String.self, forKey: .raw)) ?? ""
        query = try? container.decode([PMQueryParam].self, forKey: .query)
    }

    private enum PMUrlKeys: String, CodingKey { case raw, query }
}

private struct PMQueryParam: Decodable {
    let key: String?
    let value: String?
    let disabled: Bool?
}

private struct PMBody: Decodable {
    let mode: String?
    let raw: String?
    let urlencoded: [PMFormParam]?
    let formdata: [PMFormParam]?
    let graphql: PMGraphQL?
    let options: PMBodyOptions?
}

private struct PMFormParam: Decodable {
    let key: String
    let value: String?
    let disabled: Bool?
}

private struct PMGraphQL: Decodable {
    let query: String?
    let variables: String?
}

private struct PMBodyOptions: Decodable {
    let raw: PMRawOptions?
}

private struct PMRawOptions: Decodable {
    let language: String?
}

private struct PMAuth: Decodable {
    let type: String
    let bearer: [PMAuthParam]?
    let basic: [PMAuthParam]?
    let apikey: [PMAuthParam]?
    let oauth2: [PMAuthParam]?
    let awsv4: [PMAuthParam]?
}

private struct PMAuthParam: Decodable {
    let key: String
    let value: PMAuthValue?
}

// PMAuthValue can be String or Number
private enum PMAuthValue: Decodable {
    case string(String)
    case number(Double)

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        self = .string("")
    }
}

// MARK: - PostmanImporter

final class PostmanImporter {

    static func parse(data: Data) throws -> KoalaCollection {
        let decoder = JSONDecoder()
        let pmCollection: PMCollection
        do {
            pmCollection = try decoder.decode(PMCollection.self, from: data)
        } catch {
            throw ImportError.malformed("Could not decode Postman JSON: \(error.localizedDescription)")
        }

        guard pmCollection.info.schema.contains("v2.1") else {
            throw ImportError.unsupportedVersion(pmCollection.info.schema)
        }

        let items = pmCollection.item.map { mapItem($0) }
        return KoalaCollection(name: pmCollection.info.name, items: items)
    }

    // MARK: - Mapping helpers

    private static func mapItem(_ pmItem: PMItem) -> CollectionItem {
        if let childItems = pmItem.item {
            let folderItems = childItems.map { mapItem($0) }
            let folder = Folder(name: pmItem.name, items: folderItems)
            return .folder(folder)
        }
        let request = mapRequest(pmItem)
        return .request(request)
    }

    private static func mapRequest(_ pmItem: PMItem) -> KoalaRequest {
        let pm = pmItem.request
        let method = pmHTTPMethodValue(pm?.method ?? "GET")
        let urlString = pm?.url?.raw ?? ""

        let headers = (pm?.header ?? []).map { h in
            KeyValuePair(key: h.key, value: h.value, isEnabled: !(h.disabled ?? false))
        }

        let queryParams: [KeyValuePair]
        if let q = pm?.url?.query {
            queryParams = q.compactMap { p -> KeyValuePair? in
                guard let k = p.key else { return nil }
                return KeyValuePair(key: k, value: p.value ?? "", isEnabled: !(p.disabled ?? false))
            }
        } else {
            queryParams = []
        }

        let auth = mapAuth(pm?.auth)
        let body = mapBody(pm?.body)

        return KoalaRequest(
            name: pmItem.name,
            method: method,
            url: urlString,
            queryParams: queryParams,
            headers: headers,
            auth: auth,
            body: body
        )
    }

    private static func mapAuth(_ pmAuth: PMAuth?) -> AuthConfig {
        guard let pmAuth = pmAuth else { return .none }
        switch pmAuth.type {
        case "noauth", "none":
            return .none
        case "bearer":
            let token = pmAuth.bearer?.first(where: { $0.key == "token" })?.value?.stringValue ?? ""
            return .bearer(token: token)
        case "basic":
            let username = pmAuth.basic?.first(where: { $0.key == "username" })?.value?.stringValue ?? ""
            let password = pmAuth.basic?.first(where: { $0.key == "password" })?.value?.stringValue ?? ""
            return .basic(username: username, password: password)
        case "apikey":
            let key   = pmAuth.apikey?.first(where: { $0.key == "key" })?.value?.stringValue ?? ""
            let value = pmAuth.apikey?.first(where: { $0.key == "value" })?.value?.stringValue ?? ""
            let loc   = pmAuth.apikey?.first(where: { $0.key == "in" })?.value?.stringValue ?? "header"
            let location: APIKeyLocation = loc == "query" ? .query : .header
            return .apiKey(key: key, value: value, location: location)
        case "oauth2":
            return .oauth2(.empty)
        case "awsv4":
            let accessKey = pmAuth.awsv4?.first(where: { $0.key == "accessKey" })?.value?.stringValue ?? ""
            let secretKey = pmAuth.awsv4?.first(where: { $0.key == "secretKey" })?.value?.stringValue ?? ""
            let region    = pmAuth.awsv4?.first(where: { $0.key == "region" })?.value?.stringValue ?? ""
            let service   = pmAuth.awsv4?.first(where: { $0.key == "service" })?.value?.stringValue ?? ""
            return .awsSignature(AWSSignatureConfig(accessKeyId: accessKey, secretAccessKey: secretKey, region: region, service: service))
        default:
            return .none
        }
    }

    private static func mapBody(_ pmBody: PMBody?) -> RequestBody {
        guard let pmBody = pmBody else { return .none }
        switch pmBody.mode {
        case "raw":
            let content = pmBody.raw ?? ""
            let lang = pmBody.options?.raw?.language?.lowercased() ?? "text"
            if lang == "json" {
                return .json(content)
            }
            return .raw(content: content, contentType: contentTypeFor(language: lang))
        case "urlencoded":
            let pairs = (pmBody.urlencoded ?? []).map { p in
                KeyValuePair(key: p.key, value: p.value ?? "", isEnabled: !(p.disabled ?? false))
            }
            return .formURLEncoded(pairs)
        case "formdata":
            let items = (pmBody.formdata ?? []).map { p in
                MultipartItem(key: p.key, value: p.value ?? "", type: .text)
            }
            return .multipart(items)
        case "graphql":
            let query = pmBody.graphql?.query ?? ""
            let variables = pmBody.graphql?.variables ?? ""
            return .graphql(query: query, variables: variables)
        case "binary":
            return .none  // binary references a file; no URL available from JSON
        case "none", nil:
            return .none
        default:
            return .none
        }
    }

    private static func contentTypeFor(language: String) -> String {
        switch language {
        case "xml":  return "application/xml"
        case "html": return "text/html"
        default:     return "text/plain"
        }
    }
}

// MARK: - HTTPMethodValue convenience (file-private free function)

private func pmHTTPMethodValue(_ rawString: String) -> HTTPMethodValue {
    let upper = rawString.uppercased()
    if let method = HTTPMethod(rawValue: upper) { return .standard(method) }
    return .custom(upper)
}
