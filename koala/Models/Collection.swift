import Foundation

// MARK: - Folder

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var color: String?
    var items: [CollectionItem]
    var auth: AuthConfig?

    init(
        id: UUID = UUID(),
        name: String = "New Folder",
        color: String? = nil,
        items: [CollectionItem] = [],
        auth: AuthConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.items = items
        self.auth = auth
    }

    static var empty: Folder { Folder() }
}

// MARK: - CollectionItem

/// Discriminated union for tree nodes: either a folder (recursive) or a leaf request.
enum CollectionItem: Codable, Hashable {
    case folder(Folder)
    case request(KoalaRequest)

    // MARK: Codable — discriminator key "type"

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum ItemType: String, Codable {
        case folder, request
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .folder:
            let folder = try container.decode(Folder.self, forKey: .value)
            self = .folder(folder)
        case .request:
            let request = try container.decode(KoalaRequest.self, forKey: .value)
            self = .request(request)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let folder):
            try container.encode(ItemType.folder, forKey: .type)
            try container.encode(folder, forKey: .value)
        case .request(let request):
            try container.encode(ItemType.request, forKey: .type)
            try container.encode(request, forKey: .value)
        }
    }

    // MARK: Convenience

    var id: UUID {
        switch self {
        case .folder(let f):  return f.id
        case .request(let r): return r.id
        }
    }

    var name: String {
        switch self {
        case .folder(let f):  return f.name
        case .request(let r): return r.name
        }
    }
}

// MARK: - Collection

struct KoalaCollection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var color: String?
    var items: [CollectionItem]
    var auth: AuthConfig?
    var variables: [KeyValuePair]

    init(
        id: UUID = UUID(),
        name: String = "New Collection",
        color: String? = nil,
        items: [CollectionItem] = [],
        auth: AuthConfig? = nil,
        variables: [KeyValuePair] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.items = items
        self.auth = auth
        self.variables = variables
    }

    static var empty: KoalaCollection { KoalaCollection() }
}
