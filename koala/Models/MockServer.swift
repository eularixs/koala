import Foundation

// MARK: - MockServerStatus

enum MockServerStatus: String, Codable, CaseIterable, Identifiable {
    case live        = "live"
    case deploying   = "deploying"
    case error       = "error"
    case notDeployed = "notDeployed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .live:        return "Live"
        case .deploying:   return "Deploying"
        case .error:       return "Error"
        case .notDeployed: return "Not Deployed"
        }
    }
}

// MARK: - ResponseMode

enum ResponseMode: String, Codable, CaseIterable, Identifiable {
    case staticJSON = "staticJSON"
    case dynamicJS  = "dynamicJS"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .staticJSON: return "Static JSON"
        case .dynamicJS:  return "Dynamic JS"
        }
    }
}

// MARK: - StaticResponse

struct StaticResponse: Codable, Hashable {
    var body: String

    init(body: String = "{}") {
        self.body = body
    }

    static var empty: StaticResponse { StaticResponse() }
}

// MARK: - ConditionSource / ConditionOperator

enum ConditionSource: String, Codable, CaseIterable, Identifiable {
    case query
    case header
    case bodyJSON
    case path

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .query:    return "Query"
        case .header:   return "Header"
        case .bodyJSON: return "Body (JSON)"
        case .path:     return "Path"
        }
    }
}

enum ConditionOperator: String, Codable, CaseIterable, Identifiable {
    case equals
    case notEquals
    case contains
    case startsWith
    case exists
    case notExists

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equals:     return "equals"
        case .notEquals:  return "not equals"
        case .contains:   return "contains"
        case .startsWith: return "starts with"
        case .exists:     return "exists"
        case .notExists:  return "not exists"
        }
    }
}

// MARK: - MockCondition

struct MockCondition: Identifiable, Codable, Hashable {
    var id: UUID
    var source: ConditionSource
    var key: String
    var op: ConditionOperator
    var value: String

    init(
        id: UUID = UUID(),
        source: ConditionSource = .query,
        key: String = "",
        op: ConditionOperator = .equals,
        value: String = ""
    ) {
        self.id = id
        self.source = source
        self.key = key
        self.op = op
        self.value = value
    }
}

// MARK: - MockResponseRule

struct MockResponseRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var conditions: [MockCondition]
    var statusCode: Int
    var body: String
    var responseHeaders: [KeyValuePair]
    var delayMs: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "New Rule",
        conditions: [MockCondition] = [],
        statusCode: Int = 200,
        body: String = "{}",
        responseHeaders: [KeyValuePair] = [],
        delayMs: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.conditions = conditions
        self.statusCode = statusCode
        self.body = body
        self.responseHeaders = responseHeaders
        self.delayMs = delayMs
        self.isEnabled = isEnabled
    }
}

// MARK: - MockEndpoint

struct MockEndpoint: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var method: HTTPMethod
    var responseMode: ResponseMode
    var staticResponse: StaticResponse?
    var dynamicScript: String?
    var statusCode: Int
    var responseHeaders: [KeyValuePair]
    var delayMs: Int
    var isEnabled: Bool
    var rules: [MockResponseRule]

    init(
        id: UUID = UUID(),
        path: String = "/",
        method: HTTPMethod = .get,
        responseMode: ResponseMode = .staticJSON,
        staticResponse: StaticResponse? = StaticResponse(),
        dynamicScript: String? = nil,
        statusCode: Int = 200,
        responseHeaders: [KeyValuePair] = [],
        delayMs: Int = 0,
        isEnabled: Bool = true,
        rules: [MockResponseRule] = []
    ) {
        self.id = id
        self.path = path
        self.method = method
        self.responseMode = responseMode
        self.staticResponse = staticResponse
        self.dynamicScript = dynamicScript
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.delayMs = delayMs
        self.isEnabled = isEnabled
        self.rules = rules
    }

    // MARK: Backwards-compatible decode (missing `rules` -> [])
    private enum CodingKeys: String, CodingKey {
        case id, path, method, responseMode, staticResponse, dynamicScript
        case statusCode, responseHeaders, delayMs, isEnabled, rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        method = try c.decode(HTTPMethod.self, forKey: .method)
        responseMode = try c.decode(ResponseMode.self, forKey: .responseMode)
        staticResponse = try c.decodeIfPresent(StaticResponse.self, forKey: .staticResponse)
        dynamicScript = try c.decodeIfPresent(String.self, forKey: .dynamicScript)
        statusCode = try c.decode(Int.self, forKey: .statusCode)
        responseHeaders = (try? c.decode([KeyValuePair].self, forKey: .responseHeaders)) ?? []
        delayMs = (try? c.decode(Int.self, forKey: .delayMs)) ?? 0
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        rules = (try? c.decode([MockResponseRule].self, forKey: .rules)) ?? []
    }

    static var empty: MockEndpoint { MockEndpoint() }
}

// MARK: - MockServer

struct MockServer: Identifiable, Codable, Hashable {
    var id: UUID
    var projectId: UUID
    var name: String
    /// URL-safe slug used as path prefix on the shared Vercel deployment.
    /// All mock servers under one Koala project share the same Vercel deployment;
    /// each is namespaced by its slug at `/{slug}/{...endpoint path}`.
    var slug: String
    var vercelProjectId: String
    var deploymentURL: String
    /// Shared Edge Config storing endpoint configs across all mock servers
    /// in the same Koala project. nil until first sync.
    var edgeConfigId: String?
    var endpoints: [MockEndpoint]
    var status: MockServerStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectId: UUID = UUID(),
        name: String = "New Mock Server",
        slug: String = "",
        vercelProjectId: String = "",
        deploymentURL: String = "",
        edgeConfigId: String? = nil,
        endpoints: [MockEndpoint] = [],
        status: MockServerStatus = .notDeployed,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.slug = slug.isEmpty ? MockServer.deriveSlug(from: name) : slug
        self.vercelProjectId = vercelProjectId
        self.deploymentURL = deploymentURL
        self.edgeConfigId = edgeConfigId
        self.endpoints = endpoints
        self.status = status
        self.createdAt = createdAt
    }

    // MARK: Backwards-compatible decode
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = (try? c.decodeIfPresent(UUID.self, forKey: .projectId)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        let decodedSlug = (try? c.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        slug = decodedSlug.isEmpty ? MockServer.deriveSlug(from: name) : decodedSlug
        vercelProjectId = (try? c.decode(String.self, forKey: .vercelProjectId)) ?? ""
        deploymentURL = (try? c.decode(String.self, forKey: .deploymentURL)) ?? ""
        edgeConfigId = try? c.decodeIfPresent(String.self, forKey: .edgeConfigId)
        endpoints = (try? c.decode([MockEndpoint].self, forKey: .endpoints)) ?? []
        status = (try? c.decode(MockServerStatus.self, forKey: .status)) ?? .notDeployed
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    static func deriveSlug(from name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "default" : collapsed
    }

    static var empty: MockServer { MockServer() }
}
