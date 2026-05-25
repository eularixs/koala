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
    let name: String
    let files: [VercelDeploymentFile]
    let projectSettings: [String: String]

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
            projectSettings: ["framework": "nextjs", "buildCommand": "npm run build"]
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

    var isAuthenticated: Bool { token != nil }

    // MARK: Private

    private var token: VercelToken? {
        didSet { persistToken() }
    }

    private let keychain = KeychainService.shared
    private let keychainKey = "vercel.oauth.token"
    private let baseURL = "https://api.vercel.com"
    private let oauthTokenURL = "https://api.vercel.com/v2/oauth/access_token"
    private let oauthAuthorizeURL = "https://vercel.com/oauth/authorize"
    private let redirectURI = "koala://oauth/callback"

    // MARK: Init

    init() {
        loadTokenFromKeychain()
    }

    // MARK: - OAuth Config

    private func oauthConfig() throws -> VercelOAuthConfig {
        let env = ProcessInfo.processInfo.environment

        let clientId = Bundle.main.infoDictionary?["VercelClientId"] as? String
            ?? env["VERCEL_CLIENT_ID"]
        let clientSecret = Bundle.main.infoDictionary?["VercelClientSecret"] as? String
            ?? env["VERCEL_CLIENT_SECRET"]
        let scopes = Bundle.main.infoDictionary?["VercelOAuthScopes"] as? String
            ?? env["VERCEL_OAUTH_SCOPES"]
            ?? "user deployments"

        guard let id = clientId, !id.isEmpty,
              let secret = clientSecret, !secret.isEmpty else {
            throw VercelError.notConfigured(
                "Set VERCEL_CLIENT_ID and VERCEL_CLIENT_SECRET in scheme env or Info.plist"
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
        try keychain.delete(keychainKey)
        token = nil
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
        return try decode(VercelProject.self, from: data)
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
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(payload)
        let body = String(data: bodyData, encoding: .utf8) ?? "{}"
        let data = try await apiRawRequest(path: "/v13/deployments", method: "POST", rawBody: bodyData)
        return try decode(Deployment.self, from: data)
    }

    func getDeploymentStatus(id: String) async throws -> DeploymentStatus {
        let data = try await apiRequest(path: "/v13/deployments/\(id)", method: "GET", body: nil as String?)
        struct DeploymentResponse: Decodable { let state: DeploymentStatus }
        let response = try decode(DeploymentResponse.self, from: data)
        return response.state
    }

    // MARK: - KV

    func kvSet(key: String, value: some Encodable, kvId: String?) async throws {
        guard let kvId else { throw VercelError.notConfigured("KV store ID not set") }
        let encoded = try JSONEncoder().encode(value)
        let valueStr = String(data: encoded, encoding: .utf8) ?? "null"
        let body: [String: String] = ["key": key, "value": valueStr]
        _ = try await apiRequest(path: "/v1/edge-config/\(kvId)/items", method: "PATCH", body: body)
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
        guard let t = token else { throw VercelError.oauth("Not authenticated") }
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func apiRawRequest(path: String, method: String, rawBody: Data?) async throws -> Data {
        guard let t = token else { throw VercelError.oauth("Not authenticated") }
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawBody
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VercelError.api(statusCode: http.statusCode, message: msg)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw VercelError.decoding(error)
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
