import Foundation

// MARK: - GroupedRequest

/// A single deduplicated request within a collection group.
/// Dedup key: (method, normalizedPath). On collision, latest capture wins.
struct GroupedRequest: Identifiable {
    let id: UUID
    let method: String
    /// Path segments after the collection name, with numeric/UUID segments normalized to :id.
    let name: String
    /// Full original URL (from latest capture when deduped).
    let url: String
    let queryParams: [KeyValuePair]
    let headers: [KeyValuePair]
    let requestBody: RequestBody
    let responseStatus: Int
    let capturedAt: Date
}

// MARK: - GroupedCollection

/// All requests whose first URL path segment matches `name`.
struct GroupedCollection: Identifiable {
    let id: UUID
    let name: String
    var requests: [GroupedRequest]
}

// MARK: - RequestGroupingEngine

enum RequestGroupingEngine {

    // MARK: Public API

    /// Groups an array of `RecordedRequest` captures into collections by first path segment.
    /// - Parameter captured: Raw captures from `RecordingProxyService`.
    /// - Returns: Collections sorted by name; requests within each sorted by method+name.
    static func group(_ captured: [RecordedRequest]) -> [GroupedCollection] {
        var collectionMap: [String: [String: GroupedRequest]] = [:]

        for capture in captured {
            guard let comps = URLComponents(string: capture.url) else { continue }
            let segments = pathSegments(from: comps.path)
            guard !segments.isEmpty else { continue }

            let collectionName = segments[0]
            let requestName = normalizedRequestName(segments: Array(segments.dropFirst()))
            let dedupKey = "\(capture.method.uppercased())||\(requestName)"

            let grouped = GroupedRequest(
                id: UUID(),
                method: capture.method.uppercased(),
                name: requestName.isEmpty ? "/" : requestName,
                url: capture.url,
                queryParams: queryParams(from: comps),
                headers: redactedHeaders(from: capture.headers),
                requestBody: requestBody(from: capture),
                responseStatus: capture.responseStatus,
                capturedAt: capture.capturedAt
            )

            if collectionMap[collectionName] == nil {
                collectionMap[collectionName] = [:]
            }
            // Keep latest capture: compare capturedAt
            if let existing = collectionMap[collectionName]![dedupKey] {
                if capture.capturedAt >= existing.capturedAt {
                    collectionMap[collectionName]![dedupKey] = grouped
                }
            } else {
                collectionMap[collectionName]![dedupKey] = grouped
            }
        }

        return collectionMap
            .sorted { $0.key < $1.key }
            .map { (name, requestDict) in
                GroupedCollection(
                    id: UUID(),
                    name: name,
                    requests: requestDict.values.sorted { $0.method + $0.name < $1.method + $1.name }
                )
            }
    }

    // MARK: Path helpers

    static func pathSegments(from path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// Normalizes remaining path segments: numeric-only and UUID segments become `:id`.
    static func normalizedRequestName(segments: [String]) -> String {
        segments.map { isIdSegment($0) ? ":id" : $0 }.joined(separator: "/")
    }

    static func isIdSegment(_ segment: String) -> Bool {
        numericRegex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)) != nil
            || uuidRegex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)) != nil
    }

    // MARK: Private helpers

    private static let numericRegex = try! NSRegularExpression(pattern: #"^\d+$"#)
    private static let uuidRegex = try! NSRegularExpression(
        pattern: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
    )

    private static let sensitiveHeaders: Set<String> = ["authorization", "cookie", "set-cookie"]

    private static func redactedHeaders(from raw: [String: String]) -> [KeyValuePair] {
        raw.map { (k, v) in
            let redacted = sensitiveHeaders.contains(k.lowercased()) ? "<redacted>" : v
            return KeyValuePair(key: k, value: redacted, isEnabled: true)
        }.sorted { $0.key < $1.key }
    }

    private static func queryParams(from comps: URLComponents) -> [KeyValuePair] {
        (comps.queryItems ?? []).map {
            KeyValuePair(key: $0.name, value: $0.value ?? "", isEnabled: true)
        }
    }

    private static func requestBody(from capture: RecordedRequest) -> RequestBody {
        guard let data = capture.requestBody, !data.isEmpty else { return .none }
        let ct = capture.headers["Content-Type"] ?? capture.headers["content-type"] ?? ""
        if ct.contains("application/json"), let text = String(data: data.prefix(65536), encoding: .utf8) {
            return .json(text)
        }
        if let text = String(data: data.prefix(65536), encoding: .utf8) {
            return .raw(content: text, contentType: ct)
        }
        return .none
    }
}
