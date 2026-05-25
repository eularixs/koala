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
        isEnabled: Bool = true
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
    }

    static var empty: MockEndpoint { MockEndpoint() }
}

// MARK: - MockServer

struct MockServer: Identifiable, Codable, Hashable {
    var id: UUID
    var projectId: UUID
    var name: String
    var vercelProjectId: String
    var deploymentURL: String
    var endpoints: [MockEndpoint]
    var status: MockServerStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectId: UUID = UUID(),
        name: String = "New Mock Server",
        vercelProjectId: String = "",
        deploymentURL: String = "",
        endpoints: [MockEndpoint] = [],
        status: MockServerStatus = .notDeployed,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.vercelProjectId = vercelProjectId
        self.deploymentURL = deploymentURL
        self.endpoints = endpoints
        self.status = status
        self.createdAt = createdAt
    }

    // MARK: Backwards-compatible decode (missing projectId -> zero UUID)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = (try? c.decodeIfPresent(UUID.self, forKey: .projectId)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        vercelProjectId = (try? c.decode(String.self, forKey: .vercelProjectId)) ?? ""
        deploymentURL = (try? c.decode(String.self, forKey: .deploymentURL)) ?? ""
        endpoints = (try? c.decode([MockEndpoint].self, forKey: .endpoints)) ?? []
        status = (try? c.decode(MockServerStatus.self, forKey: .status)) ?? .notDeployed
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    static var empty: MockServer { MockServer() }
}
