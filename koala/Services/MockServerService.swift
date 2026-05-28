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

    init(vercelService: VercelService) {
        self.vercelService = vercelService
    }

    // MARK: - Create Mock Server
    //
    // Architecture:
    // - One Vercel project per Koala project (shared across all MockServer entries).
    // - One Edge Config per Koala project (stores all endpoint configs).
    // - Each MockServer has a `slug` used as URL path prefix (namespacing).
    // - First MockServer in a project triggers actual Vercel deployment.
    //   Subsequent MockServers reuse the deployment — only Edge Config + slug differ.

    func createMockServer(name: String, project: Project, appState: AppState) async throws -> MockServer {
        if !vercelService.isAuthenticated {
            try await vercelService.startOAuthFlow()
            throw MockServerError.authenticationRequired
        }
        try await vercelService.refreshTokenIfNeeded()

        isDeploying = true
        defer { isDeploying = false }

        // Check existing MockServers in this Koala project — if any, reuse infrastructure.
        let existingInProject = appState.mockServers.filter { $0.projectId == project.id }
        let serverSlug = uniqueSlug(MockServer.deriveSlug(from: name), existingSlugs: existingInProject.map(\.slug))

        // 1) Vercel project (one per Koala project)
        let vercelName = "koala-mock-\(project.slug)"
        let vercelProject = try await findOrCreateProject(named: vercelName)

        // 2) Edge Config (one per Koala project)
        let edgeConfigSlug = "koala-mock-\(project.slug)"
        let edgeConfigId = try await findOrCreateEdgeConfig(slug: edgeConfigSlug, fromExisting: existingInProject.first?.edgeConfigId)

        // 3) Connect Edge Config to Vercel project via EDGE_CONFIG env var
        let connectionString = try await vercelService.ensureEdgeConfigToken(configId: edgeConfigId)
        try? await vercelService.setProjectEnvVar(projectId: vercelProject.id, key: "EDGE_CONFIG", value: connectionString)

        // 4) Deploy template.
        // Reuse deploymentURL across MockServers in the same project ONLY if a sibling
        // MockServer already has it (i.e. template already deployed AFTER EDGE_CONFIG
        // was set). Otherwise deploy now to ensure env vars are picked up.
        let deploymentURL: String
        if let firstServer = existingInProject.first,
           !firstServer.deploymentURL.isEmpty,
           firstServer.edgeConfigId == edgeConfigId {
            deploymentURL = firstServer.deploymentURL
        } else {
            let payload = VercelDeploymentPayload.forMockServer(
                projectSlug: project.slug,
                projectName: vercelName
            )
            let deployment = try await vercelService.deployMockServer(projectId: vercelProject.id, payload: payload)
            try await pollUntilReady(deploymentId: deployment.id)
            deploymentURL = normalizeDeploymentURL(deployment.canonicalURL)
        }

        let server = MockServer(
            id: UUID(),
            projectId: project.id,
            name: name,
            slug: serverSlug,
            vercelProjectId: vercelProject.id,
            deploymentURL: deploymentURL,
            edgeConfigId: edgeConfigId,
            endpoints: [],
            status: .live,
            createdAt: Date()
        )
        appState.addMockServer(server, forProject: project.id)
        appState.updateMockBaseURL(forProject: project.id, url: deploymentURL)
        return server
    }

    private func findOrCreateProject(named name: String) async throws -> VercelProject {
        let existing = (try? await vercelService.listProjects()) ?? []
        if let match = existing.first(where: { $0.name == name }) {
            // Existing project — ensure protection disabled (idempotent).
            try? await vercelService.disableDeploymentProtection(projectId: match.id)
            return match
        }
        let created = try await vercelService.createProject(name: name)
        // New project defaults to SSO-protected. Disable so mock URLs are publicly reachable.
        try? await vercelService.disableDeploymentProtection(projectId: created.id)
        return created
    }

    private func findOrCreateEdgeConfig(slug: String, fromExisting: String?) async throws -> String {
        if let id = fromExisting, !id.isEmpty { return id }
        let configs = (try? await vercelService.listEdgeConfigs()) ?? []
        // Try exact slug match first
        if let match = configs.first(where: { $0.slug == slug }) {
            return match.id
        }
        // Vercel Hobby/Free plan caps at 1 Edge Config per account.
        // If user already has at least one, REUSE it (mock servers share via
        // key prefix mock_{slug}_{METHOD}_{path} so they don't collide).
        if let firstExisting = configs.first {
            return firstExisting.id
        }
        return try await vercelService.createEdgeConfig(slug: slug)
    }

    private func uniqueSlug(_ base: String, existingSlugs: [String]) -> String {
        let existing = Set(existingSlugs)
        if !existing.contains(base) { return base }
        var i = 2
        while existing.contains("\(base)-\(i)") { i += 1 }
        return "\(base)-\(i)"
    }

    private func normalizeDeploymentURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        return "https://" + trimmed
    }

    /// Re-syncs the BASE_URL env var with the server's current deployment URL.
    func syncMockBaseURL(_ server: MockServer, appState: AppState) {
        guard !server.deploymentURL.isEmpty else { return }
        appState.updateMockBaseURL(forProject: server.projectId, url: server.deploymentURL)
    }

    // MARK: - Endpoint Persistence

    /// Writes a single endpoint config to the shared Edge Config.
    /// Key format: `mock:{serverSlug}:{METHOD}:{path}` — matched by deployed route.ts.
    func saveEndpoint(_ endpoint: MockEndpoint, to server: MockServer) async throws {
        guard let configId = server.edgeConfigId else {
            throw MockServerError.deploymentFailed("Edge Config not initialized. Recreate the mock server.")
        }
        let key = kvKey(serverSlug: server.slug, method: endpoint.method.rawValue, path: endpoint.path)
        try await vercelService.setEdgeConfigItems([(key: key, value: endpointToConfig(endpoint))], configId: configId)
    }

    /// Batch-saves all endpoints to KV.
    func saveAllEndpoints(server: MockServer) async throws {
        for endpoint in server.endpoints {
            try await saveEndpoint(endpoint, to: server)
        }
    }

    /// Triggers a redeploy of the shared Vercel project (needed only when template/script changes).
    func deployServer(_ server: MockServer) async throws {
        guard !server.vercelProjectId.isEmpty else { return }
        isDeploying = true
        deployingServerId = server.id
        defer { isDeploying = false; deployingServerId = nil }
        let payload = VercelDeploymentPayload.forMockServer(
            projectSlug: server.slug,
            projectName: "koala-mock"
        )
        let deployment = try await vercelService.deployMockServer(projectId: server.vercelProjectId, payload: payload)
        try await pollUntilReady(deploymentId: deployment.id)
    }

    /// Removes the MockServer from local state. Does NOT delete Vercel project (shared with siblings).
    /// Only deletes the Vercel project if this is the LAST mock server for the koala project.
    func deleteMockServer(_ server: MockServer, appState: AppState) async throws {
        let siblings = appState.mockServers.filter { $0.projectId == server.projectId && $0.id != server.id }
        if siblings.isEmpty && vercelService.isAuthenticated && !server.vercelProjectId.isEmpty {
            try? await vercelService.deleteProject(id: server.vercelProjectId)
        }
        appState.removeMockServer(server.id, fromProject: server.projectId)
    }

    // MARK: - Private Helpers

    private func pollUntilReady(deploymentId: String) async throws {
        let deadline = Date().addingTimeInterval(pollTimeout)
        while Date() < deadline {
            let status = try await vercelService.getDeploymentStatus(id: deploymentId)
            if status == .ready { return }
            if status == .error {
                throw MockServerError.deploymentFailed("Vercel deployment reported error")
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw MockServerError.deploymentFailed("Deployment timed out after \(Int(pollTimeout))s")
    }

    private func kvKey(serverSlug: String, method: String, path: String) -> String {
        // serverSlug intentionally unused — single mock server per project means
        // URL has no slug prefix. Keep parameter for API stability.
        _ = serverSlug
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return "mock_\(method)_\(sanitizeKey(normalizedPath))"
    }

    /// Edge Config keys must be alphanumeric/underscore/dash. Sanitize path → key-safe form.
    private func sanitizeKey(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isLetter || ch.isNumber { out.append(ch) }
            else if ch == "_" || ch == "-" { out.append(ch) }
            else { out.append("_") }
        }
        return out
    }

    private func endpointToConfig(_ endpoint: MockEndpoint) -> [String: Any] {
        var config: [String: Any] = [
            "path": endpoint.path,
            "method": endpoint.method.rawValue,
            "responseMode": endpoint.responseMode.rawValue,
            "statusCode": endpoint.statusCode,
            "delayMs": endpoint.delayMs,
            "isEnabled": endpoint.isEnabled
        ]
        if let sr = endpoint.staticResponse {
            config["staticBody"] = sr.body
        }
        if let ds = endpoint.dynamicScript {
            config["dynamicScript"] = ds
        }
        config["responseHeaders"] = endpoint.responseHeaders.map { kv -> [String: Any] in
            ["key": kv.key, "value": kv.value, "isEnabled": kv.isEnabled]
        }
        config["rules"] = endpoint.rules.map { rule -> [String: Any] in
            [
                "id": rule.id.uuidString,
                "name": rule.name,
                "conditions": rule.conditions.map { c in
                    [
                        "source": c.source.rawValue,
                        "key": c.key,
                        "op": c.op.rawValue,
                        "value": c.value
                    ] as [String: Any]
                },
                "statusCode": rule.statusCode,
                "body": rule.body,
                "responseHeaders": rule.responseHeaders.map { kv -> [String: Any] in
                    ["key": kv.key, "value": kv.value, "isEnabled": kv.isEnabled]
                },
                "delayMs": rule.delayMs,
                "isEnabled": rule.isEnabled
            ] as [String: Any]
        }
        return config
    }
}

// MARK: - Convenience Payload init w/o serverId (no longer baked into deployment)

extension VercelDeploymentPayload {
    static func forMockServer(projectSlug: String, projectName: String) -> VercelDeploymentPayload {
        // Route file placed at root `src/app/[...path]/route.ts` so URL pattern is
        // `/{serverSlug}/{any/path}` — no required `/api/` prefix.
        let files: [VercelDeploymentFile] = [
            .init(file: "package.json", data: MockServerTemplate.packageJSON),
            .init(file: "next.config.js", data: MockServerTemplate.nextConfig),
            .init(file: "tsconfig.json", data: MockServerTemplate.tsconfigJSON),
            .init(file: "vercel.json", data: MockServerTemplate.vercelJSONShared()),
            .init(file: "src/app/[...path]/route.ts",
                  data: MockServerTemplate.routeTsShared(projectSlug: projectSlug)),
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

// MARK: - AnyEncodable (legacy, unused — kept for source compat)

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { _encode = { e in try value.encode(to: e) } }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
