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
    var collections: [KoalaCollection] = []
    var environments: [KoalaEnvironment] = []
    var globalVariables: [KeyValuePair] = []
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
        collections.append(KoalaCollection(name: name))
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll(where: { $0.id == id })
    }

    func renameCollection(_ id: UUID, to name: String) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].name = name
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
    }

    func addRequest(parentCollectionId: UUID, parentFolderId: UUID?, request: KoalaRequest) {
        guard let ci = collections.firstIndex(where: { $0.id == parentCollectionId }) else { return }
        if let folderId = parentFolderId {
            insertItem(.request(request), intoFolder: folderId, in: &collections[ci].items)
        } else {
            collections[ci].items.append(.request(request))
        }
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
            if removeItem(id: id, from: &collections[i].items) { return }
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
            if renameItem(id: id, to: name, in: &collections[i].items) { return }
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

    // MARK: Persistence

    func loadFromDisk() {
        collections = (try? persistence.loadCollections()) ?? []
        environments = (try? persistence.loadEnvironments()) ?? []
        globalVariables = (try? persistence.loadGlobals()) ?? []
    }

    func saveToDisk() {
        try? persistence.saveCollections(collections)
        try? persistence.saveEnvironments(environments)
        try? persistence.saveGlobals(globalVariables)
    }
}
