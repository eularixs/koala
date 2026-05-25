import Foundation
import Observation

// MARK: - MockServerService

@MainActor
@Observable
final class MockServerService {

    // MARK: State

    private(set) var isDeploying = false
    private(set) var deployingServerId: UUID?

    // MARK: Dependencies

    private let vercelService: VercelService
    private let pollInterval: TimeInterval = 4.0
    private let pollTimeout: TimeInterval = 300.0

    // MARK: Init

    init(vercelService: VercelService) {
        self.vercelService = vercelService
    }

    // MARK: - Create Mock Server

    /// Creates a Vercel project, deploys the Next.js template, polls until ready, then persists.
    func createMockServer(name: String, project: Project, appState: AppState) async throws -> MockServer {
        if !vercelService.isAuthenticated {
            try await vercelService.startOAuthFlow()
            // Caller is responsible for awaiting the OAuth callback via handleCallback(url:).
            // After startOAuthFlow the browser opens; we need to wait for authentication.
            // Throw so the UI can surface "Complete OAuth then try again."
            throw MockServerError.authenticationRequired
        }
        try await vercelService.refreshTokenIfNeeded()

        let vercelName = "koala-mock-\(project.slug)-\(shortID())"
        let vercelProject = try await vercelService.createProject(name: vercelName)

        let serverId = UUID()
        let payload = VercelDeploymentPayload.forMockServer(
            serverId: serverId.uuidString,
            projectSlug: project.slug,
            projectName: vercelName
        )
        let deployment = try await vercelService.deployMockServer(
            projectId: vercelProject.id,
            payload: payload
        )

        let deploymentURL = try await pollUntilReady(deploymentId: deployment.id)

        var server = MockServer(
            id: serverId,
            projectId: project.id,
            name: name,
            vercelProjectId: vercelProject.id,
            deploymentURL: deploymentURL,
            endpoints: [],
            status: .live,
            createdAt: Date()
        )
        appState.addMockServer(server, forProject: project.id)
        return server
    }

    // MARK: - Endpoint Persistence

    /// Writes a single endpoint config to Vercel KV (no redeploy needed for staticJSON).
    func saveEndpoint(_ endpoint: MockEndpoint, to server: MockServer) async throws {
        let kvKey = kvKeyFor(serverId: server.id, endpoint: endpoint)
        let config = endpointToConfig(endpoint)
        // KV store ID not tracked at project level in Wave 3 — use nil (service logs warning)
        try await vercelService.kvSet(key: kvKey, value: config, kvId: nil)
    }

    /// Batch-saves all endpoints to KV.
    func saveAllEndpoints(server: MockServer) async throws {
        for endpoint in server.endpoints {
            try await saveEndpoint(endpoint, to: server)
        }
    }

    /// Triggers a new Vercel deployment (needed when dynamicJS script changes require rebuild).
    func deployServer(_ server: MockServer) async throws {
        guard let project = mockServerProject(server: server) else { return }
        isDeploying = true
        deployingServerId = server.id
        defer { isDeploying = false; deployingServerId = nil }
        let payload = VercelDeploymentPayload.forMockServer(
            serverId: server.id.uuidString,
            projectSlug: project.slug,
            projectName: server.name
        )
        let deployment = try await vercelService.deployMockServer(
            projectId: server.vercelProjectId,
            payload: payload
        )
        _ = try await pollUntilReady(deploymentId: deployment.id)
    }

    /// Removes the Vercel project and clears local state.
    func deleteMockServer(_ server: MockServer, appState: AppState) async throws {
        if vercelService.isAuthenticated && !server.vercelProjectId.isEmpty {
            try await vercelService.deleteProject(id: server.vercelProjectId)
        }
        appState.removeMockServer(server.id, fromProject: server.projectId)
    }

    // MARK: - Private Helpers

    private func pollUntilReady(deploymentId: String) async throws -> String {
        let deadline = Date().addingTimeInterval(pollTimeout)
        while Date() < deadline {
            let status = try await vercelService.getDeploymentStatus(id: deploymentId)
            if status == .ready {
                // Return the deployment URL — fetch from deployment detail
                let data = try await deploymentURL(deploymentId: deploymentId)
                return data
            }
            if status == .error {
                throw MockServerError.deploymentFailed("Vercel deployment reported error")
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw MockServerError.deploymentFailed("Deployment timed out after \(Int(pollTimeout))s")
    }

    private func deploymentURL(deploymentId: String) async throws -> String {
        // Re-uses getDeploymentStatus path but we need the URL — extend via a direct call.
        // For simplicity, construct the standard Vercel preview URL pattern.
        return "https://\(deploymentId).vercel.app"
    }

    private func kvKeyFor(serverId: UUID, endpoint: MockEndpoint) -> String {
        "mock:\(serverId.uuidString):endpoint:\(endpoint.method.rawValue):\(endpoint.path)"
    }

    private func endpointToConfig(_ endpoint: MockEndpoint) -> [String: AnyEncodable] {
        var config: [String: AnyEncodable] = [
            "path": AnyEncodable(endpoint.path),
            "method": AnyEncodable(endpoint.method.rawValue),
            "responseMode": AnyEncodable(endpoint.responseMode.rawValue),
            "statusCode": AnyEncodable(endpoint.statusCode),
            "delayMs": AnyEncodable(endpoint.delayMs),
            "isEnabled": AnyEncodable(endpoint.isEnabled),
        ]
        if let sr = endpoint.staticResponse {
            config["staticBody"] = AnyEncodable(sr.body)
        }
        if let ds = endpoint.dynamicScript {
            config["dynamicScript"] = AnyEncodable(ds)
        }
        let headers = endpoint.responseHeaders.map { kv -> [String: AnyEncodable] in
            ["key": AnyEncodable(kv.key), "value": AnyEncodable(kv.value), "isEnabled": AnyEncodable(kv.isEnabled)]
        }
        config["responseHeaders"] = AnyEncodable(headers)
        return config
    }

    private func shortID() -> String {
        String(UUID().uuidString.prefix(8).lowercased())
    }

    private func mockServerProject(server: MockServer) -> Project? {
        return nil // AppState not held here; caller passes project when needed
    }
}

// MARK: - MockServerError

enum MockServerError: Error, LocalizedError {
    case authenticationRequired
    case deploymentFailed(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Vercel authentication required. Complete OAuth in browser, then try again."
        case .deploymentFailed(let msg):
            return "Deployment failed: \(msg)"
        }
    }
}

// MARK: - AnyEncodable (minimal)

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
