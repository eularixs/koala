import Foundation
import AppKit
import Observation

// MARK: - VercelError

enum VercelError: Error, LocalizedError {
    case notConfigured(String)
    case oauth(String)
    case api(statusCode: Int, message: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return "Vercel not configured: \(msg)"
        case .oauth(let msg): return "OAuth error: \(msg)"
        case .api(let code, let msg): return "Vercel API error \(code): \(msg)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        }
    }
}

// MARK: - VercelDeploymentFile

struct VercelDeploymentFile: Codable {
    let file: String
    let data: String
    let encoding: String

    init(file: String, data: String, encoding: String = "utf-8") {
        self.file = file
        self.data = data
        self.encoding = encoding
    }
}

// MARK: - VercelDeploymentPayload

struct VercelDeploymentPayload: Codable {
    var name: String
    var files: [VercelDeploymentFile]
    var projectSettings: [String: String]
    /// Vercel project ID this deployment belongs to. Required by /v13/deployments to link.
    var project: String?
    var target: String?

    // Builds the deployment payload for a mock server project.
    static func forMockServer(serverId: String, projectSlug: String, projectName: String) -> VercelDeploymentPayload {
        let files: [VercelDeploymentFile] = [
            .init(file: "package.json", data: MockServerTemplate.packageJSON),
            .init(file: "next.config.js", data: MockServerTemplate.nextConfig),
            .init(file: "tsconfig.json", data: MockServerTemplate.tsconfigJSON),
            .init(file: "vercel.json", data: MockServerTemplate.vercelJSON(serverId: serverId)),
            .init(file: "src/app/api/[...path]/route.ts",
                  data: MockServerTemplate.routeTs(serverId: serverId, projectSlug: projectSlug)),
        ]
        return VercelDeploymentPayload(
            name: projectName,
            files: files,
            projectSettings: ["framework": "nextjs", "buildCommand": "npm run build"],
            project: nil,
            target: "production"
        )
    }
}

// MARK: - VercelOAuthConfig

private struct VercelOAuthConfig {
    let clientId: String
    let clientSecret: String
    let scopes: String
}

// MARK: - VercelService

@MainActor
@Observable
final class VercelService {

    // MARK: State

    private(set) var currentUser: VercelUser?
    private(set) var isLoading = false

    var isAuthenticated: Bool { effectiveAccessToken != nil }

    /// Personal Access Token entered by user. Takes precedence over OAuth flow.
    private(set) var personalAccessToken: String?

    // MARK: Private

    private var token: VercelToken? {
        didSet { persistToken() }
    }

    /// Returns whichever access token should be used for API calls (PAT preferred).
    private var effectiveAccessToken: String? {
        if let pat = personalAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !pat.isEmpty {
            return pat
        }
        return token?.accessToken
    }

    private let keychain = KeychainService.shared
    private let keychainKey = "vercel.oauth.token"
    private let patKeychainKey = "vercel.personalAccessToken"
    private let baseURL = "https://api.vercel.com"
    private let oauthTokenURL = "https://api.vercel.com/v2/oauth/access_token"
    private let oauthAuthorizeURL = "https://vercel.com/oauth/authorize"
    private let redirectURI = "koala://oauth/callback"

    // MARK: Init

    init() {
        loadTokenFromKeychain()
        loadPATFromKeychain()
    }

    // MARK: - Personal Access Token

    func setPersonalAccessToken(_ token: String?) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            try keychain.set(t, for: patKeychainKey)
            personalAccessToken = t
        } else {
            try? keychain.delete(patKeychainKey)
            personalAccessToken = nil
        }
    }

    private func loadPATFromKeychain() {
        personalAccessToken = try? keychain.string(for: patKeychainKey)
    }

    // MARK: - OAuth Config

    private func oauthConfig() throws -> VercelOAuthConfig {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        let clientId = defaults.string(forKey: "VercelClientId").nonEmpty
            ?? (Bundle.main.infoDictionary?["VercelClientId"] as? String).nonEmpty
            ?? env["VERCEL_CLIENT_ID"].nonEmpty

        let storedSecret = try? KeychainService().string(for: "vercel.oauth.clientSecret")
        let clientSecret = storedSecret.nonEmpty
            ?? (Bundle.main.infoDictionary?["VercelClientSecret"] as? String).nonEmpty
            ?? env["VERCEL_CLIENT_SECRET"].nonEmpty

        let scopes = defaults.string(forKey: "VercelOAuthScopes").nonEmpty
            ?? (Bundle.main.infoDictionary?["VercelOAuthScopes"] as? String).nonEmpty
            ?? env["VERCEL_OAUTH_SCOPES"].nonEmpty
            ?? "user deployments"

        guard let id = clientId, !id.isEmpty,
              let secret = clientSecret, !secret.isEmpty else {
            throw VercelError.notConfigured(
                "Open Settings and enter your Vercel OAuth client ID + secret."
            )
        }
        return VercelOAuthConfig(clientId: id, clientSecret: secret, scopes: scopes)
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() async throws {
        let config = try oauthConfig()
        var components = URLComponents(string: oauthAuthorizeURL)!
        components.queryItems = [
            .init(name: "client_id", value: config.clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: config.scopes),
            .init(name: "response_type", value: "code"),
        ]
        guard let url = components.url else {
            throw VercelError.oauth("Failed to build OAuth URL")
        }
        await NSWorkspace.shared.open(url)
    }

    func handleCallback(url: URL) async throws {
        guard url.scheme == "koala", url.host == "oauth" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw VercelError.oauth("No code in callback URL")
        }
        try await exchangeCodeForToken(code: code)
        currentUser = try await getCurrentUser()
    }

    func refreshTokenIfNeeded() async throws {
        guard let current = token, current.isExpired,
              let refreshToken = current.refreshToken else { return }
        let config = try oauthConfig()
        let newToken = try await performTokenRefresh(refreshToken: refreshToken, config: config)
        token = newToken
    }

    func logout() throws {
        try? keychain.delete(keychainKey)
        try? keychain.delete(patKeychainKey)
        token = nil
        personalAccessToken = nil
        currentUser = nil
    }

    // MARK: - User

    func getCurrentUser() async throws -> VercelUser {
        let raw = try await apiRequest(path: "/v2/user", method: "GET", body: nil as String?)
        guard let userWrapper = try? JSONDecoder().decode([String: VercelUser].self, from: raw),
              let user = userWrapper["user"] else {
            throw VercelError.decoding(VercelError.oauth("Cannot decode user"))
        }
        return user
    }

    // MARK: - Projects

    func createProject(name: String) async throws -> VercelProject {
        let body = ["name": name, "framework": "nextjs"]
        let data = try await apiRequest(path: "/v9/projects", method: "POST", body: body)
        return try parseVercelProject(from: data)
    }

    /// Disables Vercel deployment protection (SSO) so mock endpoints are publicly reachable.
    func disableDeploymentProtection(projectId: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["ssoProtection": NSNull()])
        _ = try await apiRawRequest(path: "/v9/projects/\(projectId)", method: "PATCH", rawBody: body)
    }

    private func parseVercelProject(from data: Data) throws -> VercelProject {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = String(data: data.prefix(1200), encoding: .utf8) ?? "<non-utf8>"
            throw VercelError.decoding(NSError(domain: "VercelParse", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Project response not JSON object — raw body: \(preview)"]))
        }
        guard let id = json["id"] as? String, let name = json["name"] as? String else {
            let preview = String(data: data.prefix(1200), encoding: .utf8) ?? "<non-utf8>"
            throw VercelError.decoding(NSError(domain: "VercelParse", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Project response missing id/name — raw body: \(preview)"]))
        }
        var framework: String? = nil
        if let s = json["framework"] as? String { framework = s }
        else if let obj = json["framework"] as? [String: Any], let slug = obj["slug"] as? String { framework = slug }
        return VercelProject(id: id, name: name, framework: framework)
    }

    func deleteProject(id: String) async throws {
        _ = try await apiRequest(path: "/v9/projects/\(id)", method: "DELETE", body: nil as String?)
    }

    func listProjects() async throws -> [VercelProject] {
        let data = try await apiRequest(path: "/v9/projects", method: "GET", body: nil as String?)
        struct ProjectsResponse: Decodable { let projects: [VercelProject] }
        let response = try decode(ProjectsResponse.self, from: data)
        return response.projects
    }

    // MARK: - Deployments

    func deployMockServer(projectId: String, payload: VercelDeploymentPayload) async throws -> Deployment {
        var p = payload
        p.project = projectId
        let encoder = JSONEncoder()
        // Vercel API uses camelCase — do NOT convert to snake_case.
        let bodyData = try encoder.encode(p)
        let data = try await apiRawRequest(path: "/v13/deployments", method: "POST", rawBody: bodyData)
        return try parseDeployment(from: data)
    }

    private func parseDeployment(from data: Data) throws -> Deployment {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = String(data: data.prefix(1200), encoding: .utf8) ?? "<non-utf8>"
            throw VercelError.decoding(NSError(domain: "VercelParse", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Deployment response not JSON object — raw body: \(preview)"]))
        }
        let id = (json["id"] as? String) ?? (json["uid"] as? String) ?? ""
        guard !id.isEmpty else {
            let preview = String(data: data.prefix(1200), encoding: .utf8) ?? "<non-utf8>"
            throw VercelError.decoding(NSError(domain: "VercelParse", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Deployment response missing id/uid — raw body: \(preview)"]))
        }
        let url = (json["url"] as? String) ?? ""
        let aliases = (json["alias"] as? [String]) ?? (json["automaticAliases"] as? [String]) ?? []
        let stateStr = (json["state"] as? String) ?? (json["readyState"] as? String) ?? "QUEUED"
        let state = DeploymentStatus(rawValue: stateStr) ?? .queued
        return Deployment(id: id, url: url, aliases: aliases, state: state)
    }

    func getDeploymentStatus(id: String) async throws -> DeploymentStatus {
        let data = try await apiRequest(path: "/v13/deployments/\(id)", method: "GET", body: nil as String?)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .queued
        }
        let stateStr = (json["state"] as? String) ?? (json["readyState"] as? String) ?? "QUEUED"
        return DeploymentStatus(rawValue: stateStr) ?? .queued
    }

    // MARK: - Edge Config

    /// Lists all Edge Configs accessible to the current token.
    func listEdgeConfigs() async throws -> [(id: String, slug: String)] {
        let data = try await apiRequest(path: "/v1/edge-config", method: "GET", body: nil as String?)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap {
            guard let id = $0["id"] as? String, let slug = $0["slug"] as? String else { return nil }
            return (id, slug)
        }
    }

    /// Creates a new Vercel Edge Config store and returns its ID.
    func createEdgeConfig(slug: String) async throws -> String {
        let body = ["slug": slug]
        let data = try await apiRequest(path: "/v1/edge-config", method: "POST", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw VercelError.decoding(NSError(domain: "EdgeConfig", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "createEdgeConfig: missing id"]))
        }
        return id
    }

    /// Returns first existing token for given config, or creates a new one.
    /// Token includes read-access connection string used as `EDGE_CONFIG` env var.
    func ensureEdgeConfigToken(configId: String, label: String = "koala-read") async throws -> String {
        // List existing tokens
        let listData = try await apiRequest(path: "/v1/edge-config/\(configId)/tokens", method: "GET", body: nil as String?)
        if let arr = try? JSONSerialization.jsonObject(with: listData) as? [[String: Any]],
           let first = arr.first,
           let token = first["token"] as? String {
            return "https://edge-config.vercel.com/\(configId)?token=\(token)"
        }
        // Create new
        let body = ["label": label]
        let createData = try await apiRequest(path: "/v1/edge-config/\(configId)/token", method: "POST", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let token = json["token"] as? String else {
            throw VercelError.decoding(NSError(domain: "EdgeConfig", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "createEdgeConfigToken: missing token"]))
        }
        return "https://edge-config.vercel.com/\(configId)?token=\(token)"
    }

    /// Upserts/deletes Edge Config items. Each item: {operation, key, value}.
    func setEdgeConfigItems(_ items: [(key: String, value: Any)], configId: String) async throws {
        let payload: [String: Any] = [
            "items": items.map { ["operation": "upsert", "key": $0.key, "value": $0.value] }
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await apiRawRequest(path: "/v1/edge-config/\(configId)/items", method: "PATCH", rawBody: body)
    }

    // MARK: - Project Env Vars

    /// Sets (or upserts) an environment variable on a Vercel project.
    func setProjectEnvVar(projectId: String, key: String, value: String, targets: [String] = ["production", "preview", "development"]) async throws {
        let body: [String: Any] = [
            "key": key,
            "value": value,
            "target": targets,
            "type": "encrypted"
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        // upsert=true is needed via query param to update existing
        _ = try await apiRawRequest(path: "/v10/projects/\(projectId)/env?upsert=true", method: "POST", rawBody: data)
    }

    // MARK: - Deployments listing

    /// Returns deployment IDs for a project. Used to check if project has been deployed at all.
    func listDeployments(projectId: String, limit: Int = 1) async throws -> [String] {
        let data = try await apiRequest(path: "/v6/deployments?projectId=\(projectId)&limit=\(limit)", method: "GET", body: nil as String?)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deps = json["deployments"] as? [[String: Any]] else { return [] }
        return deps.compactMap { ($0["uid"] as? String) ?? ($0["id"] as? String) }
    }

    // MARK: - KV (legacy compat — wraps Edge Config)

    func kvSet(key: String, value: some Encodable, kvId: String?) async throws {
        guard let configId = kvId else { throw VercelError.notConfigured("Edge Config ID not set") }
        let encoded = try JSONEncoder().encode(value)
        let jsonValue = try JSONSerialization.jsonObject(with: encoded)
        try await setEdgeConfigItems([(key: key, value: jsonValue)], configId: configId)
    }

    func kvGet<T: Codable>(key: String, type: T.Type, kvId: String?) async throws -> T? {
        guard let kvId else { throw VercelError.notConfigured("KV store ID not set") }
        let data = try await apiRequest(
            path: "/v1/edge-config/\(kvId)/item/\(key)",
            method: "GET",
            body: nil as String?
        )
        guard let item = try? JSONDecoder().decode(KVItemResponse.self, from: data),
              let reEncoded = try? JSONEncoder().encode(item.value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: reEncoded)
    }

    private struct KVItemResponse: Decodable { let value: AnyCodable }

    func kvDelete(key: String, kvId: String?) async throws {
        guard let kvId else { throw VercelError.notConfigured("KV store ID not set") }
        _ = try await apiRequest(
            path: "/v1/edge-config/\(kvId)/item/\(key)",
            method: "DELETE",
            body: nil as String?
        )
    }

    // MARK: - Private Helpers

    private func exchangeCodeForToken(code: String) async throws {
        let config = try oauthConfig()
        var request = URLRequest(url: URL(string: oauthTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "code": code,
            "redirect_uri": redirectURI,
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        struct TokenResponse: Decodable {
            let accessToken: String
            let tokenType: String
            let expiresIn: Int?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
            }
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600 * 24 * 30))
        token = VercelToken(accessToken: tokenResponse.accessToken, refreshToken: nil, expiresAt: expiresAt)
    }

    private func performTokenRefresh(refreshToken: String, config: VercelOAuthConfig) async throws -> VercelToken {
        var request = URLRequest(url: URL(string: oauthTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try decode(VercelToken.self, from: data)
    }

    private func apiRequest<B: Encodable>(path: String, method: String, body: B?) async throws -> Data {
        guard let accessToken = effectiveAccessToken else { throw VercelError.oauth("Not authenticated") }
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func apiRawRequest(path: String, method: String, rawBody: Data?) async throws -> Data {
        guard let accessToken = effectiveAccessToken else { throw VercelError.oauth("Not authenticated") }
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawBody
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = extractErrorMessage(from: data)
            throw VercelError.api(statusCode: http.statusCode, message: msg)
        }
    }

    private func extractErrorMessage(from data: Data) -> String {
        // Vercel commonly returns: {"error": {"code": "X", "message": "Y"}}
        struct NestedError: Decodable {
            struct Body: Decodable { let code: String?; let message: String? }
            let error: Body
        }
        if let nested = try? JSONDecoder().decode(NestedError.self, from: data) {
            let parts = [nested.error.code, nested.error.message].compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: ": ") }
        }
        // Flat {"error": "string"}
        if let flat = try? JSONDecoder().decode([String: String].self, from: data),
           let m = flat["error"] {
            return m
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(data: data.prefix(1200), encoding: .utf8) ?? "<non-utf8>"
            let wrapped = NSError(
                domain: "VercelDecode",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) — raw body: \(preview)"]
            )
            throw VercelError.decoding(wrapped)
        }
    }

    private func persistToken() {
        if let t = token,
           let data = try? JSONEncoder().encode(t) {
            try? keychain.set(data, for: keychainKey)
        } else {
            try? keychain.delete(keychainKey)
        }
    }

    private func loadTokenFromKeychain() {
        guard let data = try? keychain.data(for: keychainKey) else { return }
        token = try? JSONDecoder().decode(VercelToken.self, from: data)
    }
}

// MARK: - AnyCodable (minimal, for KV get)

private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode(Int.self) { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(Bool.self) { value = v; return }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        default: try container.encode("")
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let v = self, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }
}
