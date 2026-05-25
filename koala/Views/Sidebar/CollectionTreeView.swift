import SwiftUI
import UniformTypeIdentifiers

// MARK: - TreeNode

private struct TreeNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let kind: Kind
    var children: [TreeNode]?

    enum Kind: Hashable {
        case collection
        case folder
        case request(HTTPMethodValue)
    }
}

// MARK: - TreeNode Builders

private func makeNodes(from collections: [KoalaCollection]) -> [TreeNode] {
    collections.map { col in
        TreeNode(
            id: col.id,
            name: col.name,
            kind: .collection,
            children: makeNodes(from: col.items)
        )
    }
}

private func makeNodes(from items: [CollectionItem]) -> [TreeNode] {
    items.map { item in
        switch item {
        case .folder(let f):
            return TreeNode(id: f.id, name: f.name, kind: .folder, children: makeNodes(from: f.items))
        case .request(let r):
            return TreeNode(id: r.id, name: r.name, kind: .request(r.method), children: nil)
        }
    }
}

// MARK: - CollectionTreeView

struct CollectionTreeView: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceState.self) private var workspaceState
    @State private var renamingId: UUID? = nil
    @State private var renameBuffer: String = ""
    @State private var addFolderParentId: UUID? = nil
    @State private var addRequestParentId: UUID? = nil
    @State private var addItemParentFolderId: UUID? = nil
    @State private var addFolderName: String = ""
    @State private var addRequestName: String = ""
    @State private var showAddFolder = false
    @State private var showAddRequest = false

    var body: some View {
        @Bindable var state = appState
        let nodes = makeNodes(from: appState.collections)

        Group {
            if nodes.isEmpty {
                Text("No collections. Click + to start.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(nodes, children: \.children, selection: $state.selectedRequestId) {
                    node in
                    treeRow(node)
                }
                .listStyle(.sidebar)
                .onChange(of: appState.selectedRequestId) { _, newId in
                    guard let id = newId, let request = appState.request(byId: id) else { return }
                    workspaceState.openRequest(request)
                }
            }
        }
        .alert("New Folder", isPresented: $showAddFolder) {
            TextField("Folder name", text: $addFolderName)
            Button("Add") {
                guard let colId = addFolderParentId else { return }
                let name = addFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    appState.addFolder(
                        parentCollectionId: colId,
                        parentFolderId: addItemParentFolderId,
                        name: name
                    )
                    appState.saveToDisk()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Request", isPresented: $showAddRequest) {
            TextField("Request name", text: $addRequestName)
            Button("Add") {
                guard let colId = addRequestParentId else { return }
                let name = addRequestName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    appState.addRequest(
                        parentCollectionId: colId,
                        parentFolderId: addItemParentFolderId,
                        request: KoalaRequest(name: name)
                    )
                    appState.saveToDisk()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Row

    @ViewBuilder
    private func treeRow(_ node: TreeNode) -> some View {
        let isSelectable: Bool = {
            if case .request = node.kind { return true }
            return false
        }()

        Group {
            if renamingId == node.id {
                TextField("", text: $renameBuffer)
                    .onSubmit {
                        let name = renameBuffer.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            if node.kind == .collection {
                                appState.renameCollection(node.id, to: name)
                            } else {
                                appState.renameItem(id: node.id, to: name)
                            }
                            appState.saveToDisk()
                        }
                        renamingId = nil
                    }
                    .textFieldStyle(.plain)
            } else {
                rowLabel(for: node)
                    .onTapGesture(count: 2) {
                        beginRename(node)
                    }
                    .contextMenu { contextMenuItems(for: node) }
                    .onDrag { NSItemProvider(object: node.id.uuidString as NSString) }
            }
        }
        .selectionDisabled(!isSelectable)
    }

    @ViewBuilder
    private func rowLabel(for node: TreeNode) -> some View {
        switch node.kind {
        case .collection:
            Label(node.name, systemImage: "folder")
                .fontWeight(.semibold)
        case .folder:
            Label(node.name, systemImage: "folder.fill")
        case .request(let method):
            HStack(spacing: 6) {
                Text(method.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(method.color, in: RoundedRectangle(cornerRadius: 3))
                Text(node.name)
            }
        }
    }

    // MARK: Context Menu

    @ViewBuilder
    private func contextMenuItems(for node: TreeNode) -> some View {
        switch node.kind {
        case .collection:
            Button("Rename") { beginRename(node) }
            Button("Duplicate") { duplicateCollection(node.id) }
            Button("New Folder") { beginAddFolder(collectionId: node.id, parentFolderId: nil) }
            Button("New Request") { beginAddRequest(collectionId: node.id, parentFolderId: nil) }
            Divider()
            Button("Delete", role: .destructive) {
                appState.deleteCollection(node.id)
                appState.saveToDisk()
            }

        case .folder:
            Button("Rename") { beginRename(node) }
            Button("Duplicate") { duplicateFolder(node.id) }
            Button("New Folder") {
                let colId = owningCollectionId(of: node.id)
                beginAddFolder(collectionId: colId, parentFolderId: node.id)
            }
            Button("New Request") {
                let colId = owningCollectionId(of: node.id)
                beginAddRequest(collectionId: colId, parentFolderId: node.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                appState.deleteItem(id: node.id)
                appState.saveToDisk()
            }

        case .request:
            Button("Rename") { beginRename(node) }
            Button("Duplicate") { duplicateRequest(node.id) }
            Button("Open in New Tab") {
                if let request = appState.request(byId: node.id) {
                    workspaceState.openRequest(request)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                appState.deleteItem(id: node.id)
                appState.saveToDisk()
            }
        }
    }

    // MARK: Rename

    private func beginRename(_ node: TreeNode) {
        renameBuffer = node.name
        renamingId = node.id
    }

    // MARK: Add helpers

    private func beginAddFolder(collectionId: UUID?, parentFolderId: UUID?) {
        addFolderParentId = collectionId
        addItemParentFolderId = parentFolderId
        addFolderName = ""
        showAddFolder = true
    }

    private func beginAddRequest(collectionId: UUID?, parentFolderId: UUID?) {
        addRequestParentId = collectionId
        addItemParentFolderId = parentFolderId
        addRequestName = ""
        showAddRequest = true
    }

    // MARK: Duplicate helpers

    private func duplicateCollection(_ id: UUID) {
        guard let col = appState.collections.first(where: { $0.id == id }) else { return }
        var copy = col
        copy.id = UUID()
        copy.name = col.name + " Copy"
        appState.collections.append(copy)
        appState.saveToDisk()
    }

    private func duplicateFolder(_ id: UUID) {
        for i in appState.collections.indices {
            if duplicateItem(id: id, in: &appState.collections[i].items) {
                appState.saveToDisk()
                return
            }
        }
    }

    private func duplicateRequest(_ id: UUID) {
        for i in appState.collections.indices {
            if duplicateItem(id: id, in: &appState.collections[i].items) {
                appState.saveToDisk()
                return
            }
        }
    }

    @discardableResult
    private func duplicateItem(id: UUID, in items: inout [CollectionItem]) -> Bool {
        for i in items.indices {
            switch items[i] {
            case .request(let r) where r.id == id:
                var copy = r; copy.id = UUID(); copy.name = r.name + " Copy"
                items.insert(.request(copy), at: i + 1)
                return true
            case .folder(let f) where f.id == id:
                var copy = f; copy.id = UUID(); copy.name = f.name + " Copy"
                items.insert(.folder(copy), at: i + 1)
                return true
            case .folder(var f):
                if duplicateItem(id: id, in: &f.items) {
                    items[i] = .folder(f)
                    return true
                }
            default: continue
            }
        }
        return false
    }

    // MARK: Helpers

    private func owningCollectionId(of itemId: UUID) -> UUID? {
        appState.collections.first(where: { containsItem(id: itemId, in: $0.items) })?.id
    }

    private func containsItem(id: UUID, in items: [CollectionItem]) -> Bool {
        for item in items {
            if item.id == id { return true }
            if case .folder(let f) = item, containsItem(id: id, in: f.items) { return true }
        }
        return false
    }
}
