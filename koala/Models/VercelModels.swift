import Foundation

// MARK: - VercelToken

struct VercelToken: Codable, Hashable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { expiresAt < Date() }

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt    = "expires_at"
    }
}

// MARK: - VercelUser

struct VercelUser: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var email: String

    enum CodingKeys: String, CodingKey {
        case id    = "id"
        case name  = "name"
        case email = "email"
    }
}

// MARK: - VercelProject

struct VercelProject: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var framework: String?

    enum CodingKeys: String, CodingKey {
        case id, name, framework
    }

    init(id: String, name: String, framework: String? = nil) {
        self.id = id
        self.name = name
        self.framework = framework
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Vercel returns framework as a string slug OR an object { slug, name } OR null depending on endpoint/version.
        if let str = try? c.decodeIfPresent(String.self, forKey: .framework) {
            framework = str
        } else if let obj = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .framework) {
            framework = obj["slug"]?.value as? String
        } else {
            framework = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(framework, forKey: .framework)
    }
}

// Lightweight AnyCodable for tolerant decode of mixed Vercel response shapes.
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { value = v; return }
        if let v = try? c.decode(Int.self) { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(Bool.self) { value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) {
            value = v.mapValues { $0.value }
            return
        }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let b as Bool: try c.encode(b)
        default: try c.encodeNil()
        }
    }
}

// MARK: - DeploymentStatus

enum DeploymentStatus: String, Codable, CaseIterable, Identifiable {
    case queued   = "QUEUED"
    case building = "BUILDING"
    case ready    = "READY"
    case error    = "ERROR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .queued:   return "Queued"
        case .building: return "Building"
        case .ready:    return "Ready"
        case .error:    return "Error"
        }
    }
}

// MARK: - Deployment

struct Deployment: Identifiable, Codable, Hashable {
    var id: String
    /// Unique per-deployment URL (random suffix). Use `aliases.first` for stable production URL.
    var url: String
    /// Stable production aliases (no random suffix). Use [0] for canonical URL.
    var aliases: [String]
    var state: DeploymentStatus

    enum CodingKeys: String, CodingKey {
        case id, uid, url, alias, state, readyState
    }

    init(id: String, url: String, aliases: [String] = [], state: DeploymentStatus) {
        self.id = id
        self.url = url
        self.aliases = aliases
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let idValue = (try? c.decodeIfPresent(String.self, forKey: .id))
                  ?? (try? c.decodeIfPresent(String.self, forKey: .uid))
        guard let resolvedId = idValue else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Missing both `id` and `uid` keys")
        }
        id = resolvedId
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        aliases = (try? c.decodeIfPresent([String].self, forKey: .alias)) ?? []
        let s = (try? c.decodeIfPresent(DeploymentStatus.self, forKey: .state))
             ?? (try? c.decodeIfPresent(DeploymentStatus.self, forKey: .readyState))
        state = s ?? .queued
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encode(aliases, forKey: .alias)
        try c.encode(state, forKey: .state)
    }

    /// Canonical URL preferring stable alias over per-deployment URL.
    var canonicalURL: String { aliases.first ?? url }
}
