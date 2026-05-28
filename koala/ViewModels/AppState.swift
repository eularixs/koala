import Foundation
import Observation

// MARK: - SidebarSection

enum SidebarSection: Hashable, CaseIterable {
    case collections
    case environments
    case mockServers
    case history
    case recording
    case automation

    var label: String {
        switch self {
        case .collections:  return "Collections"
        case .environments: return "Environments"
        case .mockServers:  return "Mock Servers"
        case .history:      return "History"
        case .recording:    return "Recording"
        case .automation:   return "Automation"
        }
    }

    var systemImage: String {
        switch self {
        case .collections:  return "folder"
        case .environments: return "leaf"
        case .mockServers:  return "server.rack"
        case .history:      return "clock"
        case .recording:    return "antenna.radiowaves.left.and.right"
        case .automation:   return "clock.arrow.circlepath"
        }
    }
}

// MARK: - AppState

@MainActor
@Observable
final class AppState {
    // MARK: Projects
    var projects: [Project] = []
    var activeProjectId: UUID? = nil

    var activeProject: Project? {
        guard let id = activeProjectId else { return nil }
        return projects.first(where: { $0.id == id })
    }

    // MARK: Per-project slices (private storage)
    private var collectionsByProject: [UUID: [KoalaCollection]] = [:]
    private var environmentsByProject: [UUID: [KoalaEnvironment]] = [:]
    private var globalsByProject: [UUID: [KeyValuePair]] = [:]

    // MARK: - Wave 3: Mock Servers slice
    private var mockServersByProject: [UUID: [MockServer]] = [:]

    /// Mock servers for the currently active project.
    var mockServers: [MockServer] {
        get { mockServersByProject[activeProjectId ?? UUID()] ?? [] }
        set {
            guard let id = activeProjectId else { return }
            mockServersByProject[id] = newValue
        }
    }

    /// Selection state for the mock server detail pane.
    var selectedMockServerId: UUID? = nil

    // MARK: - Runner Settings slice (per request, per project)
    private var runnerSettingsByProject: [UUID: [UUID: RunnerSettings]] = [:]

    /// Per-request runner settings for the currently active project.
    var runnerSettings: [UUID: RunnerSettings] {
        get { runnerSettingsByProject[activeProjectId ?? UUID()] ?? [:] }
        set {
            guard let id = activeProjectId else { return }
            runnerSettingsByProject[id] = newValue
        }
    }

    func runnerSetting(for requestId: UUID) -> RunnerSettings? {
        runnerSettings[requestId]
    }

    func setRunnerSettings(_ s: RunnerSettings, for requestId: UUID) {
        guard let pid = activeProjectId else { return }
        if runnerSettingsByProject[pid] == nil {
            runnerSettingsByProject[pid] = [:]
        }
        runnerSettingsByProject[pid]![requestId] = s
        try? persistence.saveRunnerSettings(runnerSettingsByProject[pid] ?? [:], forProject: pid)
    }

    // MARK: Computed accessors (existing shape preserved)
    var collections: [KoalaCollection] {
        get { collectionsByProject[activeProjectId ?? UUID()] ?? [] }
        set {
            guard let id = activeProjectId else { return }
            collectionsByProject[id] = newValue
        }
    }

    var environments: [KoalaEnvironment] {
        get { environmentsByProject[activeProjectId ?? UUID()] ?? [] }
        set {
            guard let id = activeProjectId else { return }
            environmentsByProject[id] = newValue
        }
    }

    var globalVariables: [KeyValuePair] {
        get { globalsByProject[activeProjectId ?? UUID()] ?? [] }
        set {
            guard let id = activeProjectId else { return }
            globalsByProject[id] = newValue
        }
    }

    // MARK: Selection State
    var selectedEnvironmentId: UUID? = nil
    /// Env id currently being EDITED in the right-panel detail (separate from
    /// the active env used in requests).
    var environmentDetailId: UUID? = nil
    var selectedRequestId: UUID? = nil
    var selectedSidebarSection: SidebarSection = .collections

    private let persistence = PersistenceService()

    // MARK: - Cookie purge hook
    //
    // The main agent wires this to `CookieJarService.purge(envId:)` at app
    // startup. AppState intentionally does not own the cookie jar — cookies
    // live in `CookieJarService`. Call sites that delete an environment
    // invoke `purgeCookiesForDeletedEnv(_:)`; if no hook is wired, it's a
    // no-op (cookies will simply remain orphaned on disk until cleared).
    var onPurgeCookiesForEnv: ((UUID) -> Void)? = nil

    /// Notify the cookie jar that an environment has been deleted so its
    /// cookies can be purged from memory + disk.
    func purgeCookiesForDeletedEnv(_ id: UUID) {
        onPurgeCookiesForEnv?(id)
    }

    var selectedEnvironment: KoalaEnvironment? {
        guard let id = selectedEnvironmentId else { return nil }
        return environments.first(where: { $0.id == id })
    }

    // MARK: Request Lookup

    func request(byId id: UUID) -> KoalaRequest? {
        for collection in collections {
            if let found = findRequest(id: id, in: collection.items) { return found }
        }
        return nil
    }

    private func findRequest(id: UUID, in items: [CollectionItem]) -> KoalaRequest? {
        for item in items {
            switch item {
            case .request(let r) where r.id == id: return r
            case .folder(let f):
                if let found = findRequest(id: id, in: f.items) { return found }
            default: continue
            }
        }
        return nil
    }

    // MARK: Update Request

    func updateRequest(_ updated: KoalaRequest) {
        for i in collections.indices {
            if updateRequest(updated, in: &collections[i].items) { return }
        }
    }

    @discardableResult
    private func updateRequest(_ updated: KoalaRequest, in items: inout [CollectionItem]) -> Bool {
        for i in items.indices {
            switch items[i] {
            case .request(let r) where r.id == updated.id:
                items[i] = .request(updated)
                return true
            case .folder(var f):
                if updateRequest(updated, in: &f.items) {
                    items[i] = .folder(f)
                    return true
                }
            default: continue
            }
        }
        return false
    }

    // MARK: Recording → Project

    /// Inserts `collections` directly into the specified project without switching the active project.
    /// Called by `RecordingProxyService.saveAsProject`.
    func insertCollections(_ collections: [KoalaCollection], forProject projectId: UUID) {
        if collectionsByProject[projectId] == nil {
            collectionsByProject[projectId] = []
        }
        collectionsByProject[projectId]!.append(contentsOf: collections)
        try? persistence.saveCollections(collectionsByProject[projectId]!, forProject: projectId)
        saveManifest()
    }

    // MARK: Collection CRUD

    func addCollection(_ name: String) {
        let projectId = activeProjectId ?? UUID()
        collections.append(KoalaCollection(projectId: projectId, name: name))
        saveActiveProject()
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll(where: { $0.id == id })
        saveActiveProject()
    }

    func renameCollection(_ id: UUID, to name: String) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].name = name
        saveActiveProject()
    }

    // MARK: Folder / Request Add

    func addFolder(parentCollectionId: UUID, parentFolderId: UUID?, name: String) {
        let folder = Folder(name: name)
        guard let ci = collections.firstIndex(where: { $0.id == parentCollectionId }) else { return }
        if let folderId = parentFolderId {
            insertItem(.folder(folder), intoFolder: folderId, in: &collections[ci].items)
        } else {
            collections[ci].items.append(.folder(folder))
        }
        saveActiveProject()
    }

    func addRequest(parentCollectionId: UUID, parentFolderId: UUID?, request: KoalaRequest) {
        guard let ci = collections.firstIndex(where: { $0.id == parentCollectionId }) else { return }
        if let folderId = parentFolderId {
            insertItem(.request(request), intoFolder: folderId, in: &collections[ci].items)
        } else {
            collections[ci].items.append(.request(request))
        }
        saveActiveProject()
    }

    @discardableResult
    private func insertItem(_ newItem: CollectionItem, intoFolder folderId: UUID, in items: inout [CollectionItem]) -> Bool {
        for i in items.indices {
            switch items[i] {
            case .folder(var f) where f.id == folderId:
                f.items.append(newItem)
                items[i] = .folder(f)
                return true
            case .folder(var f):
                if insertItem(newItem, intoFolder: folderId, in: &f.items) {
                    items[i] = .folder(f)
                    return true
                }
            default: continue
            }
        }
        return false
    }

    // MARK: Delete Item (recursive)

    func deleteItem(id: UUID) {
        for i in collections.indices {
            if removeItem(id: id, from: &collections[i].items) {
                saveActiveProject()
                return
            }
        }
    }

    @discardableResult
    private func removeItem(id: UUID, from items: inout [CollectionItem]) -> Bool {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: idx)
            return true
        }
        for i in items.indices {
            if case .folder(var f) = items[i] {
                if removeItem(id: id, from: &f.items) {
                    items[i] = .folder(f)
                    return true
                }
            }
        }
        return false
    }

    // MARK: Rename Item (recursive)

    func renameItem(id: UUID, to name: String) {
        for i in collections.indices {
            if renameItem(id: id, to: name, in: &collections[i].items) {
                saveActiveProject()
                return
            }
        }
    }

    @discardableResult
    private func renameItem(id: UUID, to name: String, in items: inout [CollectionItem]) -> Bool {
        for i in items.indices {
            switch items[i] {
            case .request(var r) where r.id == id:
                r.name = name
                items[i] = .request(r)
                return true
            case .folder(var f) where f.id == id:
                f.name = name
                items[i] = .folder(f)
                return true
            case .folder(var f):
                if renameItem(id: id, to: name, in: &f.items) {
                    items[i] = .folder(f)
                    return true
                }
            default: continue
            }
        }
        return false
    }

    // MARK: - Wave 3: Mock Server CRUD

    func addMockServer(_ server: MockServer, forProject projectId: UUID) {
        if mockServersByProject[projectId] == nil {
            mockServersByProject[projectId] = []
        }
        mockServersByProject[projectId]!.append(server)
        saveMockServersForProject(projectId)
    }

    func removeMockServer(_ id: UUID, fromProject projectId: UUID) {
        mockServersByProject[projectId]?.removeAll(where: { $0.id == id })
        if selectedMockServerId == id { selectedMockServerId = nil }
        saveMockServersForProject(projectId)
    }

    func updateMockServer(_ server: MockServer) {
        guard let idx = mockServersByProject[server.projectId]?.firstIndex(where: { $0.id == server.id }) else { return }
        mockServersByProject[server.projectId]![idx] = server
        saveMockServersForProject(server.projectId)
    }

    func renameMockServer(_ id: UUID, to name: String) {
        guard let pid = activeProjectId,
              let idx = mockServersByProject[pid]?.firstIndex(where: { $0.id == id }) else { return }
        mockServersByProject[pid]![idx].name = name
        saveMockServersForProject(pid)
    }

    private func saveMockServersForProject(_ id: UUID) {
        try? persistence.saveMockServers(mockServersByProject[id] ?? [], forProject: id)
    }

    // MARK: Project Management

    @discardableResult
    func createProject(name: String) -> Project {
        let baseSlug = Project.deriveSlug(from: name)
        let slug = uniqueSlug(baseSlug)
        let project = Project(name: name, slug: slug)
        projects.append(project)
        return project
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].name = name
        projects[i].updatedAt = Date()
    }

    func setSlug(_ slug: String, for id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].slug = slug
        projects[i].updatedAt = Date()
    }

    func setColor(_ hex: String?, for id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].color = hex
        projects[i].updatedAt = Date()
        saveManifest()
    }

    func setGroupName(_ groupName: String?, for id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = groupName?.trimmingCharacters(in: .whitespaces)
        projects[i].groupName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        projects[i].updatedAt = Date()
        saveManifest()
    }

    private var customGroupNames: [String] = []

    /// Available project tags (env labels). Persisted in manifest.
    var tags: [ProjectTag] = ProjectTag.defaults

    func setTag(_ tagId: UUID?, for projectId: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].tagId = tagId
        projects[idx].updatedAt = Date()
        saveManifest()
    }

    func upsertTag(_ tag: ProjectTag) {
        if let i = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[i] = tag
        } else {
            tags.append(tag)
        }
        saveManifest()
    }

    func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        for i in projects.indices where projects[i].tagId == id {
            projects[i].tagId = nil
        }
        saveManifest()
    }

    func tag(byId id: UUID?) -> ProjectTag? {
        guard let id else { return nil }
        return tags.first(where: { $0.id == id })
    }

    func addCustomGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !customGroupNames.contains(trimmed) && !projects.contains(where: { $0.groupName == trimmed }) {
            customGroupNames.append(trimmed)
            saveManifest()
        }
    }

    func removeCustomGroup(_ name: String) {
        customGroupNames.removeAll { $0 == name }
        saveManifest()
    }

    var projectGroups: [String] {
        let fromProjects = projects.compactMap { $0.groupName }
        return Array(Set(fromProjects + customGroupNames)).sorted()
    }

    func deleteProject(_ id: UUID) {
        try? persistence.deleteProjectData(id)
        collectionsByProject.removeValue(forKey: id)
        environmentsByProject.removeValue(forKey: id)
        globalsByProject.removeValue(forKey: id)
        mockServersByProject.removeValue(forKey: id)
        runnerSettingsByProject.removeValue(forKey: id)
        projects.removeAll(where: { $0.id == id })
        if activeProjectId == id {
            activeProjectId = projects.first?.id
        }
        saveManifest()
    }

    func switchProject(to id: UUID) {
        guard projects.contains(where: { $0.id == id }) else { return }
        if collectionsByProject[id] == nil {
            loadProjectSlices(id)
        }
        activeProjectId = id
        autoSelectDefaultEnvironment()
        saveManifest()
    }

    /// If no env selected (or selection points to an env from another project),
    /// pick the env named "default" (case insensitive) for the active project.
    private func autoSelectDefaultEnvironment() {
        let projectEnvs = environments
        let currentValid = selectedEnvironmentId.flatMap { id in
            projectEnvs.first(where: { $0.id == id })
        } != nil
        if currentValid { return }
        if let def = projectEnvs.first(where: { $0.name.lowercased() == "default" }) {
            selectedEnvironmentId = def.id
        } else {
            selectedEnvironmentId = nil
        }
    }

    // MARK: Persistence

    func loadFromDisk() {
        let manifest = (try? persistence.loadProjects()) ?? ProjectsManifest()

        if manifest.projects.isEmpty {
            let slug = uniqueSlug("default")
            let defaultProject = Project(name: "Default", slug: slug)
            projects = [defaultProject]
            activeProjectId = defaultProject.id
            customGroupNames = []
            saveManifest()
        } else {
            projects = manifest.projects
            activeProjectId = manifest.activeProjectId ?? manifest.projects.first?.id
            customGroupNames = manifest.customGroupNames
            tags = manifest.tags.isEmpty ? ProjectTag.defaults : manifest.tags
        }

        if let id = activeProjectId {
            loadProjectSlices(id)
            autoSelectDefaultEnvironment()
        }
    }

    func saveToDisk() {
        saveManifest()
        saveActiveProject()
    }

    // MARK: - Mock Environment

    /// Ensures a "Mock Cloud" environment exists for the given project.
    /// Called after loading project slices.
    func ensureMockEnvironment(forProject id: UUID) {
        // Migrate legacy MOCK_BASE_URL → BASE_URL in any existing Mock Cloud env
        migrateLegacyMockBaseURL(forProject: id)

        let hasMock = (environmentsByProject[id] ?? []).contains(where: { $0.name == "Mock Cloud" })
        guard !hasMock else { return }

        let mockEnv = KoalaEnvironment(
            projectId: id,
            name: "Mock Cloud",
            color: "#22B8CF",
            variables: [
                EnvVariable(key: "BASE_URL", value: "https://koala-mock.vercel.app", isEnabled: true)
            ]
        )
        if environmentsByProject[id] == nil {
            environmentsByProject[id] = []
        }
        environmentsByProject[id]!.append(mockEnv)
        try? persistence.saveEnvironments(environmentsByProject[id]!, forProject: id)
    }

    /// One-shot migration: renames `MOCK_BASE_URL` → `BASE_URL` in the Mock Cloud env.
    /// Safe to call repeatedly (no-op once migrated).
    private func migrateLegacyMockBaseURL(forProject id: UUID) {
        guard var envs = environmentsByProject[id] else { return }
        var mutated = false
        for envIdx in envs.indices where envs[envIdx].name == "Mock Cloud" {
            var env = envs[envIdx]
            for varIdx in env.variables.indices where env.variables[varIdx].key == "MOCK_BASE_URL" {
                // If BASE_URL already exists, drop legacy duplicate; otherwise rename.
                if env.variables.contains(where: { $0.key == "BASE_URL" }) {
                    env.variables.remove(at: varIdx)
                } else {
                    env.variables[varIdx].key = "BASE_URL"
                }
                mutated = true
                break
            }
            envs[envIdx] = env
        }
        if mutated {
            environmentsByProject[id] = envs
            try? persistence.saveEnvironments(envs, forProject: id)
        }
    }

    /// Updates the `BASE_URL` variable in the "Mock Cloud" environment for the given project.
    /// Creates the env if missing.
    func updateMockBaseURL(forProject id: UUID, url: String) {
        ensureMockEnvironment(forProject: id)
        guard var envs = environmentsByProject[id],
              let envIdx = envs.firstIndex(where: { $0.name == "Mock Cloud" }) else { return }
        var env = envs[envIdx]
        if let varIdx = env.variables.firstIndex(where: { $0.key == "BASE_URL" }) {
            env.variables[varIdx].value = url
            env.variables[varIdx].isEnabled = true
        } else {
            env.variables.append(EnvVariable(key: "BASE_URL", value: url, isEnabled: true))
        }
        envs[envIdx] = env
        environmentsByProject[id] = envs
        try? persistence.saveEnvironments(envs, forProject: id)
    }

    // MARK: Private Helpers

    private func loadProjectSlices(_ id: UUID) {
        collectionsByProject[id] = (try? persistence.loadCollections(forProject: id)) ?? []
        environmentsByProject[id] = (try? persistence.loadEnvironments(forProject: id)) ?? []
        globalsByProject[id] = (try? persistence.loadGlobals(forProject: id)) ?? []
        var loadedServers = (try? persistence.loadMockServers(forProject: id)) ?? []
        let projectSlug = projects.first(where: { $0.id == id })?.slug ?? ""
        var mutated = false
        for sIdx in loadedServers.indices {
            let fixed = AppState.canonicalDeploymentURL(loadedServers[sIdx].deploymentURL, projectSlug: projectSlug)
            if fixed != loadedServers[sIdx].deploymentURL {
                loadedServers[sIdx].deploymentURL = fixed
                mutated = true
            }
        }
        if mutated {
            try? persistence.saveMockServers(loadedServers, forProject: id)
        }
        mockServersByProject[id] = loadedServers
        runnerSettingsByProject[id] = (try? persistence.loadRunnerSettings(forProject: id)) ?? [:]
        // Sync BASE_URL env to the canonical URL of the first server (if any).
        if let first = loadedServers.first, !first.deploymentURL.isEmpty {
            updateMockBaseURL(forProject: id, url: first.deploymentURL)
        }
        ensureMockEnvironment(forProject: id)
    }

    /// Strips the 9-char per-deployment random ID from a stored mock URL, leaving the
    /// stable production alias. e.g.
    ///   `https://koala-mock-test-group-mhubkqc65-team.vercel.app`
    ///   → `https://koala-mock-test-group-team.vercel.app`
    static func canonicalDeploymentURL(_ raw: String, projectSlug: String) -> String {
        guard !projectSlug.isEmpty, raw.contains(".vercel.app") else { return raw }
        let marker = "koala-mock-\(projectSlug)-"
        guard let mStart = raw.range(of: marker),
              let appEnd = raw.range(of: ".vercel.app") else { return raw }
        let between = String(raw[mStart.upperBound..<appEnd.lowerBound])
        let parts = between.split(separator: "-", maxSplits: 1).map(String.init)
        // Heuristic: per-deployment id is exactly 9 lowercase alphanumeric chars.
        guard parts.count == 2,
              parts[0].count == 9,
              parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return raw
        }
        return String(raw[..<mStart.upperBound]) + parts[1] + String(raw[appEnd.lowerBound...])
    }

    func saveActiveProject() {
        guard let id = activeProjectId else { return }
        try? persistence.saveCollections(collectionsByProject[id] ?? [], forProject: id)
        try? persistence.saveEnvironments(environmentsByProject[id] ?? [], forProject: id)
        try? persistence.saveGlobals(globalsByProject[id] ?? [], forProject: id)
    }

    private func saveManifest() {
        let manifest = ProjectsManifest(projects: projects, activeProjectId: activeProjectId, customGroupNames: customGroupNames, tags: tags)
        try? persistence.saveProjects(manifest)
    }

    private func uniqueSlug(_ base: String) -> String {
        let existing = Set(projects.map(\.slug))
        if !existing.contains(base) { return base }
        var counter = 2
        while existing.contains("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }

    // MARK: - Collaboration Bundle

    /// Builds a Codable snapshot of all collaborative data for a project.
    ///
    /// Vault-flagged variables (`isVault == true`) have their `value` cleared
    /// before bundling. The model-level encode also strips them, but we wipe
    /// in-memory copies here as defence-in-depth so any future serialization
    /// path (e.g. logging the bundle) cannot leak secrets.
    func collaborationBundle(forProject id: UUID) -> CollaborationBundle {
        var envs = environmentsByProject[id] ?? []
        for ei in envs.indices {
            for vi in envs[ei].variables.indices where envs[ei].variables[vi].isVault {
                envs[ei].variables[vi].value = ""
            }
        }
        var globals = globalsByProject[id] ?? []
        for gi in globals.indices where globals[gi].isVault {
            globals[gi].value = ""
        }
        return CollaborationBundle(
            collections: collectionsByProject[id] ?? [],
            environments: envs,
            globalVariables: globals,
            schemaVersion: CollaborationBundle.currentSchemaVersion
        )
    }

    // MARK: - Vault

    /// Optional injection point — wired in `StateContainer.init`. Kept optional
    /// so `AppState` can be unit-tested without Keychain access.
    var vaultService: VaultService? = nil

    /// Convenience read-through to `VaultService`.
    func vaultValue(name: String, projectId: UUID) -> String? {
        vaultService?.get(name, projectId: projectId)
    }

    /// Replaces local collections/environments/globals for a project and persists.
    func applyCollaborationBundle(_ bundle: CollaborationBundle, forProject id: UUID) {
        collectionsByProject[id] = bundle.collections
        environmentsByProject[id] = bundle.environments
        globalsByProject[id] = bundle.globalVariables
        try? persistence.saveCollections(bundle.collections, forProject: id)
        try? persistence.saveEnvironments(bundle.environments, forProject: id)
        try? persistence.saveGlobals(bundle.globalVariables, forProject: id)
        ensureMockEnvironment(forProject: id)
    }

    /// Stores the Vercel Edge Config ID for a project's collab data and persists manifest.
    func setCollabEdgeConfigId(_ configId: String?, forProject id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].collabEdgeConfigId = configId
        projects[i].updatedAt = Date()
        saveManifest()
    }
}

// MARK: - CollaborationBundle

/// Codable snapshot pushed to / pulled from Vercel Edge Config.
struct CollaborationBundle: Codable {
    var collections: [KoalaCollection]
    var environments: [KoalaEnvironment]
    var globalVariables: [KeyValuePair]
    var schemaVersion: Int

    static let currentSchemaVersion: Int = 1

    init(
        collections: [KoalaCollection] = [],
        environments: [KoalaEnvironment] = [],
        globalVariables: [KeyValuePair] = [],
        schemaVersion: Int = CollaborationBundle.currentSchemaVersion
    ) {
        self.collections = collections
        self.environments = environments
        self.globalVariables = globalVariables
        self.schemaVersion = schemaVersion
    }
}
