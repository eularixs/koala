import Foundation
import Observation

// MARK: - CollaborationError

enum CollaborationError: Error, LocalizedError {
    case notConfigured
    case notAuthenticated
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No collaboration store linked. Push first to create one."
        case .notAuthenticated:
            return "Vercel authentication required. Sign in via Settings, then try again."
        case .syncFailed(let msg):
            return "Sync failed: \(msg)"
        }
    }
}

// MARK: - CollaborationService

/// Pushes / pulls a project's collaboration bundle (collections + environments + globals)
/// to a per-project Vercel Edge Config store.
@MainActor
@Observable
final class CollaborationService {

    // MARK: State

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    // MARK: Dependencies

    private let vercelService: VercelService

    // MARK: Constants

    /// Edge Config item key holding the bundle JSON.
    private let bundleKey = "bundle"

    // MARK: - Share Key

    /// Compact share key payload — encodes everything a teammate needs to pull this project.
    private struct ShareKeyPayload: Codable {
        let edgeConfigId: String
        let readToken: String
        let projectName: String
        let projectSlug: String
        let schemaVersion: Int
    }

    /// Generates a shareable invite key. Owner sends this to teammates; teammates paste it
    /// into the welcome screen "Join Project" dialog to import the project.
    /// Requires the project to have been pushed at least once (Edge Config initialized).
    func generateShareKey(projectId: UUID, appState: AppState) async throws -> String {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw CollaborationError.syncFailed("Project not found")
        }
        guard vercelService.isAuthenticated else { throw CollaborationError.notAuthenticated }
        guard let configId = project.collabEdgeConfigId, !configId.isEmpty else {
            throw CollaborationError.notConfigured
        }
        try await vercelService.refreshTokenIfNeeded()

        // Ensure a read token exists; ensureEdgeConfigToken returns the FULL connection URL.
        let connectionURL = try await vercelService.ensureEdgeConfigToken(configId: configId)
        // Extract bare token from `https://edge-config.vercel.com/{id}?token=XYZ`
        let token = URLComponents(string: connectionURL)?
            .queryItems?.first(where: { $0.name == "token" })?.value ?? ""

        let payload = ShareKeyPayload(
            edgeConfigId: configId,
            readToken: token,
            projectName: project.name,
            projectSlug: project.slug,
            schemaVersion: 1
        )
        let data = try JSONEncoder().encode(payload)
        return data.base64EncodedString()
    }

    /// Joins a project via a share key. Creates a local Project pointing at the remote
    /// Edge Config, fetches bundle once, applies it. Does NOT require Vercel PAT on this
    /// side — Edge Config read endpoint accepts the embedded token directly.
    func joinViaShareKey(_ key: String, appState: AppState) async throws -> Project {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed) else {
            throw CollaborationError.syncFailed("Invalid share key (not base64)")
        }
        let payload: ShareKeyPayload
        do {
            payload = try JSONDecoder().decode(ShareKeyPayload.self, from: data)
        } catch {
            throw CollaborationError.syncFailed("Invalid share key format")
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // Fetch bundle directly via public Edge Config HTTPS endpoint (no PAT needed).
        let urlStr = "https://edge-config.vercel.com/\(payload.edgeConfigId)/item/\(bundleKey)?token=\(payload.readToken)"
        guard let url = URL(string: urlStr) else {
            throw CollaborationError.syncFailed("Could not build Edge Config URL")
        }
        let (raw, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CollaborationError.syncFailed("Pull failed (\(http.statusCode))")
        }
        let bundle: CollaborationBundle
        do {
            bundle = try JSONDecoder().decode(CollaborationBundle.self, from: raw)
        } catch {
            throw CollaborationError.syncFailed("Bundle decode failed: \(error.localizedDescription)")
        }

        // Create local Project (or reuse if slug already exists).
        let projectId: UUID
        if let existing = appState.projects.first(where: { $0.slug == payload.projectSlug }) {
            projectId = existing.id
        } else {
            let created = appState.createProject(name: payload.projectName)
            appState.setSlug(payload.projectSlug, for: created.id)
            appState.setCollabEdgeConfigId(payload.edgeConfigId, forProject: created.id)
            projectId = created.id
        }

        appState.applyCollaborationBundle(bundle, forProject: projectId)
        lastSyncDate = Date()
        return appState.projects.first(where: { $0.id == projectId })!
    }

    // MARK: Init

    init(vercelService: VercelService) {
        self.vercelService = vercelService
    }

    // MARK: - Push

    /// Serializes the project's bundle and writes it to its Edge Config store.
    /// Creates the store on first push and stores the ID back on the Project.
    func pushProject(projectId: UUID, appState: AppState) async throws {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw CollaborationError.syncFailed("Project not found")
        }
        guard vercelService.isAuthenticated else {
            lastError = CollaborationError.notAuthenticated.errorDescription
            throw CollaborationError.notAuthenticated
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            try await vercelService.refreshTokenIfNeeded()

            // Reuse mock server's Edge Config if available (single store per Koala project).
            // Vercel Hobby caps at 1 Edge Config per account, so sharing is mandatory there.
            let configId = try await resolveEdgeConfigId(projectId: projectId, project: project, appState: appState)

            let bundle = appState.collaborationBundle(forProject: projectId)
            try await vercelService.kvSet(key: bundleKey, value: bundle, kvId: configId)

            lastSyncDate = Date()
        } catch let err as CollaborationError {
            lastError = err.errorDescription
            throw err
        } catch {
            let msg = error.localizedDescription
            lastError = msg
            throw CollaborationError.syncFailed(msg)
        }
    }

    /// Order of preference:
    /// 1. Project.collabEdgeConfigId (already linked)
    /// 2. Existing mock server's edgeConfigId for this project (shared store)
    /// 3. Existing Edge Config on Vercel with slug `koala-{slug}` (reuse)
    /// 4. Create new one
    private func resolveEdgeConfigId(projectId: UUID, project: Project, appState: AppState) async throws -> String {
        if let existing = project.collabEdgeConfigId, !existing.isEmpty {
            return existing
        }
        // Reuse mock server's Edge Config if present
        if let mockEC = appState.mockServers.first(where: { $0.projectId == projectId })?.edgeConfigId,
           !mockEC.isEmpty {
            appState.setCollabEdgeConfigId(mockEC, forProject: projectId)
            return mockEC
        }
        // Reuse any existing Edge Config matching slug
        let slug = "koala-mock-\(project.slug)"
        let configs = (try? await vercelService.listEdgeConfigs()) ?? []
        if let match = configs.first(where: { $0.slug == slug }) {
            appState.setCollabEdgeConfigId(match.id, forProject: projectId)
            return match.id
        }
        // Fallback: create new (only happens if no mock + no existing store)
        let created = try await vercelService.createEdgeConfig(slug: slug)
        appState.setCollabEdgeConfigId(created, forProject: projectId)
        return created
    }

    // MARK: - Pull

    /// Fetches the bundle from Edge Config and replaces local state for the project.
    func pullProject(projectId: UUID, appState: AppState) async throws {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw CollaborationError.syncFailed("Project not found")
        }
        guard vercelService.isAuthenticated else {
            lastError = CollaborationError.notAuthenticated.errorDescription
            throw CollaborationError.notAuthenticated
        }
        guard let configId = project.collabEdgeConfigId, !configId.isEmpty else {
            lastError = CollaborationError.notConfigured.errorDescription
            throw CollaborationError.notConfigured
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            try await vercelService.refreshTokenIfNeeded()

            guard let bundle = try await vercelService.kvGet(
                key: bundleKey,
                type: CollaborationBundle.self,
                kvId: configId
            ) else {
                throw CollaborationError.syncFailed("Bundle not found in Edge Config")
            }

            appState.applyCollaborationBundle(bundle, forProject: projectId)
            lastSyncDate = Date()
        } catch let err as CollaborationError {
            lastError = err.errorDescription
            throw err
        } catch {
            let msg = error.localizedDescription
            lastError = msg
            throw CollaborationError.syncFailed(msg)
        }
    }
}
