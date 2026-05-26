import Foundation
import Observation

// MARK: - SidebarSection

enum SidebarSection: Hashable, CaseIterable {
    case collections
    case environments
    case mockServers
    case history

    var label: String {
        switch self {
        case .collections:  return "Collections"
        case .environments: return "Environments"
        case .mockServers:  return "Mock Servers"
        case .history:      return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .collections:  return "folder"
        case .environments: return "leaf"
        case .mockServers:  return "server.rack"
        case .history:      return "clock"
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
    var selectedRequestId: UUID? = nil
    var selectedSidebarSection: SidebarSection = .collections

    private let persistence = PersistenceService()

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

    var projectGroups: [String] {
        Array(Set(projects.compactMap { $0.groupName })).sorted()
    }

    func deleteProject(_ id: UUID) {
        try? persistence.deleteProjectData(id)
        collectionsByProject.removeValue(forKey: id)
        environmentsByProject.removeValue(forKey: id)
        globalsByProject.removeValue(forKey: id)
        mockServersByProject.removeValue(forKey: id)
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
        saveManifest()
    }

    // MARK: Persistence

    func loadFromDisk() {
        let manifest = (try? persistence.loadProjects()) ?? ProjectsManifest()

        if manifest.projects.isEmpty {
            let slug = uniqueSlug("default")
            let defaultProject = Project(name: "Default", slug: slug)
            projects = [defaultProject]
            activeProjectId = defaultProject.id
            saveManifest()
        } else {
            projects = manifest.projects
            activeProjectId = manifest.activeProjectId ?? manifest.projects.first?.id
        }

        if let id = activeProjectId {
            loadProjectSlices(id)
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
        let hasMock = (environmentsByProject[id] ?? []).contains(where: { $0.name == "Mock Cloud" })
        guard !hasMock else { return }

        let mockEnv = KoalaEnvironment(
            projectId: id,
            name: "Mock Cloud",
            color: "#22B8CF",
            variables: [
                EnvVariable(key: "MOCK_BASE_URL", value: "https://koala-mock.vercel.app", isEnabled: true)
            ]
        )
        if environmentsByProject[id] == nil {
            environmentsByProject[id] = []
        }
        environmentsByProject[id]!.append(mockEnv)
        try? persistence.saveEnvironments(environmentsByProject[id]!, forProject: id)
    }

    // MARK: Private Helpers

    private func loadProjectSlices(_ id: UUID) {
        collectionsByProject[id] = (try? persistence.loadCollections(forProject: id)) ?? []
        environmentsByProject[id] = (try? persistence.loadEnvironments(forProject: id)) ?? []
        globalsByProject[id] = (try? persistence.loadGlobals(forProject: id)) ?? []
        mockServersByProject[id] = (try? persistence.loadMockServers(forProject: id)) ?? []
        ensureMockEnvironment(forProject: id)
    }

    func saveActiveProject() {
        guard let id = activeProjectId else { return }
        try? persistence.saveCollections(collectionsByProject[id] ?? [], forProject: id)
        try? persistence.saveEnvironments(environmentsByProject[id] ?? [], forProject: id)
        try? persistence.saveGlobals(globalsByProject[id] ?? [], forProject: id)
    }

    private func saveManifest() {
        let manifest = ProjectsManifest(projects: projects, activeProjectId: activeProjectId)
        try? persistence.saveProjects(manifest)
    }

    private func uniqueSlug(_ base: String) -> String {
        let existing = Set(projects.map(\.slug))
        if !existing.contains(base) { return base }
        var counter = 2
        while existing.contains("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }
}
