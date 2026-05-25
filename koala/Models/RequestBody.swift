import Foundation

// MARK: - MultipartItem

enum MultipartItemType: String, Codable, CaseIterable, Identifiable {
    case text = "text"
    case file = "file"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct MultipartItem: Identifiable, Codable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var type: MultipartItemType
    var fileURL: URL?

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        type: MultipartItemType = .text,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.type = type
        self.fileURL = fileURL
    }

    static var empty: MultipartItem { MultipartItem() }
}

// MARK: - RequestBody

enum RequestBody: Codable, Hashable {
    case none
    case json(String)
    case formURLEncoded([KeyValuePair])
    case multipart([MultipartItem])
    case raw(content: String, contentType: String)
    case graphql(query: String, variables: String)
    case binary(URL)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, content, contentType, pairs, items, query, variables, url
    }

    private enum BodyType: String, Codable {
        case none, json, formURLEncoded, multipart, raw, graphql, binary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BodyType.self, forKey: .type)
        switch type {
        case .none:
            self = .none
        case .json:
            let content = try container.decode(String.self, forKey: .content)
            self = .json(content)
        case .formURLEncoded:
            let pairs = try container.decode([KeyValuePair].self, forKey: .pairs)
            self = .formURLEncoded(pairs)
        case .multipart:
            let items = try container.decode([MultipartItem].self, forKey: .items)
            self = .multipart(items)
        case .raw:
            let content     = try container.decode(String.self, forKey: .content)
            let contentType = try container.decode(String.self, forKey: .contentType)
            self = .raw(content: content, contentType: contentType)
        case .graphql:
            let query     = try container.decode(String.self, forKey: .query)
            let variables = try container.decode(String.self, forKey: .variables)
            self = .graphql(query: query, variables: variables)
        case .binary:
            let url = try container.decode(URL.self, forKey: .url)
            self = .binary(url)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(BodyType.none, forKey: .type)
        case .json(let content):
            try container.encode(BodyType.json, forKey: .type)
            try container.encode(content, forKey: .content)
        case .formURLEncoded(let pairs):
            try container.encode(BodyType.formURLEncoded, forKey: .type)
            try container.encode(pairs, forKey: .pairs)
        case .multipart(let items):
            try container.encode(BodyType.multipart, forKey: .type)
            try container.encode(items, forKey: .items)
        case .raw(let content, let contentType):
            try container.encode(BodyType.raw, forKey: .type)
            try container.encode(content, forKey: .content)
            try container.encode(contentType, forKey: .contentType)
        case .graphql(let query, let variables):
            try container.encode(BodyType.graphql, forKey: .type)
            try container.encode(query, forKey: .query)
            try container.encode(variables, forKey: .variables)
        case .binary(let url):
            try container.encode(BodyType.binary, forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }

    // MARK: UI helpers

    var displayName: String {
        switch self {
        case .none:           return "None"
        case .json:           return "JSON"
        case .formURLEncoded: return "Form URL-Encoded"
        case .multipart:      return "Multipart"
        case .raw:            return "Raw"
        case .graphql:        return "GraphQL"
        case .binary:         return "Binary"
        }
    }
}
