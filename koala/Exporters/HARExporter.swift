import Foundation

// MARK: - HAR 1.2 output DTOs
// Spec: http://www.softwareishard.com/blog/har-12-spec/

private struct HAROutLog: Encodable {
    let log: HAROutLogBody
}

private struct HAROutLogBody: Encodable {
    let version: String = "1.2"
    let creator: HAROutCreator
    let entries: [HAROutEntry]
}

private struct HAROutCreator: Encodable {
    let name: String = "Koala"
    let version: String = "0.1.0"
}

private struct HAROutEntry: Encodable {
    let startedDateTime: String
    let time: Int = -1
    let request: HAROutRequest
    let response: HAROutResponse
    let cache: HAROutCache
    let timings: HAROutTimings
}

private struct HAROutRequest: Encodable {
    let method: String
    let url: String
    let httpVersion: String = "HTTP/1.1"
    let cookies: [HAROutNameValue]
    let headers: [HAROutNameValue]
    let queryString: [HAROutNameValue]
    let postData: HAROutPostData?
    let headersSize: Int = -1
    let bodySize: Int = -1
}

private struct HAROutResponse: Encodable {
    let status: Int = 0
    let statusText: String = ""
    let httpVersion: String = "HTTP/1.1"
    let cookies: [HAROutNameValue] = []
    let headers: [HAROutNameValue] = []
    let content: HAROutContent
    let redirectURL: String = ""
    let headersSize: Int = -1
    let bodySize: Int = -1
}

private struct HAROutContent: Encodable {
    let size: Int = 0
    let mimeType: String = "text/plain"
    let text: String = ""
}

private struct HAROutCache: Encodable {}

private struct HAROutTimings: Encodable {
    let send: Int = -1
    let wait: Int = -1
    let receive: Int = -1
}

private struct HAROutNameValue: Encodable {
    let name: String
    let value: String
}

private struct HAROutPostData: Encodable {
    let mimeType: String
    let text: String
}

// MARK: - HARExporter

final class HARExporter {

    static func export(_ collection: KoalaCollection) throws -> Data {
        let requests = collectRequests(items: collection.items)
        let entries = requests.map(mapEntry)
        let log = HAROutLog(
            log: HAROutLogBody(creator: HAROutCreator(), entries: entries)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(log)
    }

    // MARK: - Mapping helpers

    private static func collectRequests(items: [CollectionItem]) -> [KoalaRequest] {
        var out: [KoalaRequest] = []
        for item in items {
            switch item {
            case .folder(let folder):
                out.append(contentsOf: collectRequests(items: folder.items))
            case .request(let req):
                out.append(req)
            }
        }
        return out
    }

    private static func mapEntry(_ req: KoalaRequest) -> HAROutEntry {
        HAROutEntry(
            startedDateTime: iso8601Formatter.string(from: req.updatedAt),
            request: mapRequest(req),
            response: HAROutResponse(content: HAROutContent()),
            cache: HAROutCache(),
            timings: HAROutTimings()
        )
    }

    private static func mapRequest(_ req: KoalaRequest) -> HAROutRequest {
        let headers = req.headers
            .filter { $0.isEnabled }
            .map { HAROutNameValue(name: $0.key, value: $0.value) }
        let query = req.queryParams
            .filter { $0.isEnabled }
            .map { HAROutNameValue(name: $0.key, value: $0.value) }
        return HAROutRequest(
            method: req.method.rawValue,
            url: req.url,
            cookies: [],
            headers: headers,
            queryString: query,
            postData: mapPostData(req.body)
        )
    }

    private static func mapPostData(_ body: RequestBody) -> HAROutPostData? {
        switch body {
        case .none:
            return nil
        case .json(let content):
            return HAROutPostData(mimeType: "application/json", text: content)
        case .raw(let content, let contentType):
            return HAROutPostData(mimeType: contentType.isEmpty ? "text/plain" : contentType,
                                  text: content)
        case .formURLEncoded(let pairs):
            let text = pairs
                .filter { $0.isEnabled }
                .map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
                .joined(separator: "&")
            return HAROutPostData(mimeType: "application/x-www-form-urlencoded", text: text)
        case .multipart:
            return HAROutPostData(mimeType: "multipart/form-data", text: "")
        case .graphql(let query, let variables):
            let payload: [String: Any] = ["query": query, "variables": variables]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            return HAROutPostData(mimeType: "application/json", text: text)
        case .binary:
            return HAROutPostData(mimeType: "application/octet-stream", text: "")
        }
    }

    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
