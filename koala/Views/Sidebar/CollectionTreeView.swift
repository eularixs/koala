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
    /// Optional — present only after LicenseService is injected at the env root.
    /// When absent (e.g. early dev), gating gracefully falls open.
    @Environment(LicenseService.self) private var licenseService: LicenseService?
    /// Optional — present after AutomationSchedulerService is injected at the
    /// env root. When absent, "Schedule Run..." is hidden.
    @Environment(AutomationSchedulerService.self) private var scheduler: AutomationSchedulerService?

    /// Optional callback from sidebar host to open the "New Collection" dialog.
    var onRequestNew: (() -> Void)? = nil

    @State private var renamingId: UUID? = nil
    @State private var renameBuffer: String = ""
    @State private var addFolderParentId: UUID? = nil
    @State private var addRequestParentId: UUID? = nil
    @State private var addItemParentFolderId: UUID? = nil
    @State private var addFolderName: String = ""
    @State private var addRequestName: String = ""
    @State private var showAddFolder = false
    @State private var showAddRequest = false

    /// Persisted per-project: UUIDs of collections/folders currently expanded.
    @State private var expanded: Set<UUID> = []

    /// Collection currently being run via the Run Collection sheet.
    @State private var runCollection: KoalaCollection? = nil

    /// Collection pre-selected for a new schedule via "Schedule Run..." menu.
    @State private var scheduleForCollectionId: UUID? = nil

    var body: some View {
        @Bindable var state = appState
        let nodes = makeNodes(from: appState.collections)

        VStack(spacing: 0) {
            sectionHeader
            Divider()
            Group {
                if nodes.isEmpty {
                    Text("No collections. Click + to start.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $state.selectedRequestId) {
                        ForEach(nodes) { node in
                            treeNodeView(node)
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: appState.selectedRequestId) { _, newId in
                        guard let id = newId, let request = appState.request(byId: id) else { return }
                        workspaceState.openRequest(request)
                    }
                }
            }
        }
        .onAppear { loadExpansion(appState.activeProjectId) }
        .onChange(of: appState.activeProjectId) { _, new in loadExpansion(new) }
        .onChange(of: expanded) { _, _ in saveExpansion(appState.activeProjectId) }
        .sheet(item: $runCollection) { col in
            RunCollectionSheet(collection: col)
                .environment(appState)
        }
        .sheet(item: Binding(
            get: { scheduleForCollectionId.map { IdentifiedUUID(id: $0) } },
            set: { scheduleForCollectionId = $0?.id }
        )) { wrapper in
            if let scheduler {
                ScheduleEditorSheet(editing: nil, preselectedCollectionId: wrapper.id)
                    .environment(appState)
                    .environment(scheduler)
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

    // MARK: Section Header

    private var sectionHeader: some View {
        HStack {
            Text("Collections")
                .font(.headline)
                .padding(.leading, 12)
            Spacer()
            Button {
                onRequestNew?()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    // MARK: Recursive Node View (with persisted expansion)

    @ViewBuilder
    private func treeNodeView(_ node: TreeNode) -> some View {
        TreeNodeRecursiveView(
            node: node,
            expanded: $expanded,
            renderRow: { n in AnyView(treeRow(n).tag(n.id)) }
        )
    }

    // MARK: Expansion Persistence

    private func expansionKey(_ pid: UUID) -> String { "expanded.\(pid.uuidString)" }

    private func loadExpansion(_ projectId: UUID?) {
        guard let pid = projectId else { expanded = []; return }
        guard let data = UserDefaults.standard.data(forKey: expansionKey(pid)),
              let set = try? JSONDecoder().decode(Set<UUID>.self, from: data) else {
            expanded = []
            return
        }
        expanded = set
    }

    private func saveExpansion(_ projectId: UUID?) {
        guard let pid = projectId,
              let data = try? JSONEncoder().encode(expanded) else { return }
        UserDefaults.standard.set(data, forKey: expansionKey(pid))
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
                HStack(spacing: 6) {
                    rowIcon(for: node)
                    TextField("", text: $renameBuffer)
                        .textFieldStyle(.plain)
                        .onSubmit { commitRename(node) }
                        .onExitCommand { renamingId = nil }
                }
            } else {
                rowLabel(for: node)
                    // Use simultaneousGesture so List's single-tap selection still fires.
                    // .onTapGesture(count: 2) would consume single taps too on macOS lists.
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        beginRename(node)
                    })
                    .contextMenu { contextMenuItems(for: node) }
                    .onDrag { NSItemProvider(object: node.id.uuidString as NSString) }
            }
        }
        .selectionDisabled(!isSelectable)
    }

    /// Just the leading icon / method badge — no name. Used during rename mode
    /// so the visual identity (folder icon, GET badge, etc.) stays in place.
    @ViewBuilder
    private func rowIcon(for node: TreeNode) -> some View {
        switch node.kind {
        case .collection:
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        case .folder:
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
        case .request(let method):
            Text(method.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(method.color, in: RoundedRectangle(cornerRadius: 3))
        }
    }

    private func commitRename(_ node: TreeNode) {
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
            Button("Run Collection...") {
                if let col = appState.collections.first(where: { $0.id == node.id }) {
                    runCollection = col
                }
            }
            scheduleRunMenuItem(for: node.id)
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

    // MARK: Schedule Run (Pro)

    @ViewBuilder
    private func scheduleRunMenuItem(for collectionId: UUID) -> some View {
        // Hide entirely when Pro features are disabled at compile/runtime.
        if FeatureFlags.proEnabled, scheduler != nil {
            let isPro = licenseService?.isPro ?? true
            if isPro {
                Button("Schedule Run...") {
                    scheduleForCollectionId = collectionId
                }
            } else {
                Button("\u{1F512} Schedule Run... (Pro)") {}
                    .disabled(true)
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

// MARK: - IdentifiedUUID
//
// Small wrapper so a UUID can drive a `.sheet(item:)` binding.

private struct IdentifiedUUID: Identifiable, Hashable {
    let id: UUID
}

// MARK: - TreeNodeRecursiveView
//
// Extracted so SwiftUI can give each node a stable view identity. Using AnyView
// inline in a recursive `@ViewBuilder` returns the same opaque shell each level
// and confuses List's selection tracking — leading to "click 3x to select" bug.

private struct TreeNodeRecursiveView: View {
    let node: TreeNode
    @Binding var expanded: Set<UUID>
    let renderRow: (TreeNode) -> AnyView

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expanded.contains(node.id) },
                    set: { isOpen in
                        if isOpen { expanded.insert(node.id) }
                        else { expanded.remove(node.id) }
                    }
                )
            ) {
                ForEach(children) { child in
                    TreeNodeRecursiveView(node: child, expanded: $expanded, renderRow: renderRow)
                }
            } label: {
                renderRow(node)
            }
        } else {
            renderRow(node)
        }
    }
}
