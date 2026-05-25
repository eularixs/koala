import SwiftUI
import UniformTypeIdentifiers

struct WelcomeWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportExportService.self) private var importExportService

    let onPicked: () -> Void

    @State private var showCreateSheet = false
    @State private var editingProject: Project? = nil
    @State private var showImporter = false
    @State private var importError: String? = nil
    @State private var showImportError = false
    @State private var showSettings = false
    @State private var search = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            Divider().opacity(0.4)
            projectsList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 880, height: 560)
        .background(
            WindowConfigurator(
                hideMinimize: true,
                hideZoom: true,
                resizable: false,
                minSize: NSSize(width: 880, height: 560),
                maxSize: NSSize(width: 880, height: 560)
            )
        )
        .sheet(isPresented: $showCreateSheet) {
            ProjectFormSheet(
                title: "New Project",
                initial: Project(name: "", slug: ""),
                onSubmit: { project, group in
                    let created = appState.createProject(name: project.name)
                    if !project.slug.isEmpty {
                        appState.setSlug(project.slug, for: created.id)
                    }
                    appState.setColor(project.color, for: created.id)
                    appState.setGroupName(group, for: created.id)
                    appState.switchProject(to: created.id)
                    showCreateSheet = false
                    onPicked()
                },
                onCancel: { showCreateSheet = false }
            )
        }
        .sheet(item: $editingProject) { project in
            ProjectFormSheet(
                title: "Edit Project",
                initial: project,
                onSubmit: { updated, group in
                    appState.renameProject(project.id, to: updated.name)
                    appState.setSlug(updated.slug, for: project.id)
                    appState.setColor(updated.color, for: project.id)
                    appState.setGroupName(group, for: project.id)
                    editingProject = nil
                },
                onCancel: { editingProject = nil }
            )
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .data, .plainText],
            allowsMultipleSelection: false
        ) { result in handleImport(result) }
        .alert("Import Error", isPresented: $showImportError, presenting: importError) { _ in
            Button("OK") {}
        } message: { Text($0) }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer().frame(height: 38)

            VStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Koala")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 8) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create Project", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showImporter = true
                } label: {
                    Label("Import from Other App", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Projects list

    private var projectsList: some View {
        VStack(spacing: 0) {
            actionToolbar
                .padding(.horizontal, 14)
                .padding(.top, 32)
                .padding(.bottom, 10)

            if appState.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4, pinnedViews: []) {
                        ForEach(groupedFiltered, id: \.0) { groupName, members in
                            groupSection(groupName: groupName, members: members)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .alert("New Group", isPresented: $showNewGroupAlert) {
            TextField("Group name", text: $newGroupName)
            Button("Create") {
                let g = newGroupName.trimmingCharacters(in: .whitespaces)
                if !g.isEmpty { collapsedGroups.remove(g) }
                newGroupName = ""
            }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("Groups become visible when you assign a project to them via Edit.")
        }
    }

    private var actionToolbar: some View {
        HStack(spacing: 8) {
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .help("New project")

            Button {
                newGroupName = ""
                showNewGroupAlert = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 22, height: 22)
            }
            .help("New group")

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("", text: $search, prompt: Text("Search projects..."))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 260)
        }
    }

    @ViewBuilder
    private func groupSection(groupName: String, members: [Project]) -> some View {
        let isCollapsed = collapsedGroups.contains(groupName)
        VStack(spacing: 2) {
            Button {
                if isCollapsed { collapsedGroups.remove(groupName) }
                else { collapsedGroups.insert(groupName) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Circle()
                        .fill(groupColor(for: members))
                        .frame(width: 8, height: 8)
                    Text(groupName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(members.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                ForEach(members) { project in
                    ProjectRow(project: project) {
                        openProject(project)
                    } onEdit: {
                        editingProject = project
                    } onDelete: {
                        appState.deleteProject(project.id)
                    }
                }
            }
        }
    }

    private func groupColor(for members: [Project]) -> Color {
        if let hex = members.first?.color, let c = Color(hex: hex) { return c }
        return .secondary.opacity(0.5)
    }

    private var groupedFiltered: [(String, [Project])] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = appState.projects.filter {
            needle.isEmpty
                || $0.name.lowercased().contains(needle)
                || $0.slug.lowercased().contains(needle)
                || ($0.groupName ?? "").lowercased().contains(needle)
        }
        let grouped = Dictionary(grouping: matching) { $0.groupName ?? "Ungrouped" }
        return grouped
            .map { ($0.key, $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { lhs, rhs in
                if lhs.0 == "Ungrouped" { return false }
                if rhs.0 == "Ungrouped" { return true }
                return lhs.0 < rhs.0
            }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No projects yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Click \"Create Project\" to get started.")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openProject(_ project: Project) {
        appState.switchProject(to: project.id)
        onPicked()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
            showImportError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let project = appState.createProject(name: url.deletingPathExtension().lastPathComponent)
            appState.switchProject(to: project.id)
            do {
                try importExportService.importFile(at: url, into: project.id, appState: appState)
                onPicked()
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }
}

// MARK: - ProjectRow

private struct ProjectRow: View {
    let project: Project
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: project.color ?? "") ?? .secondary.opacity(0.4))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(project.slug)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(relativeDate(project.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Menu {
                    Button("Edit...", action: onEdit)
                    Divider()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(hovering ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .alert("Delete Project?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(project.name)\" and all its data will be permanently removed.")
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ProjectFormSheet (borderless Apple-style)

struct ProjectFormSheet: View {
    let title: String
    let initial: Project
    let onSubmit: (Project, String?) -> Void
    let onCancel: () -> Void

    @Environment(AppState.self) private var appState

    @State private var name: String = ""
    @State private var slug: String = ""
    @State private var color: String? = nil
    @State private var groupName: String = ""
    @State private var slugManuallyEdited: Bool = false

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                row(label: "Name") {
                    TextField("", text: $name, prompt: Text("e.g. Eularix"))
                        .textFieldStyle(.plain)
                        .onChange(of: name) { _, new in
                            if !slugManuallyEdited { slug = Project.deriveSlug(from: new) }
                        }
                }
                Divider()
                row(label: "Slug") {
                    TextField("", text: $slug, prompt: Text("eularix"))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: slug) { _, _ in slugManuallyEdited = true }
                }
                Divider()
                row(label: "Group") {
                    HStack {
                        TextField("", text: $groupName, prompt: Text("Ungrouped"))
                            .textFieldStyle(.plain)
                        if !appState.projectGroups.isEmpty {
                            Menu {
                                ForEach(appState.projectGroups, id: \.self) { g in
                                    Button(g) { groupName = g }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                }
                Divider()
                row(label: "Color") {
                    HStack(spacing: 6) {
                        ForEach(palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if color == hex {
                                        Circle().stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { color = hex }
                        }
                        Button {
                            color = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear color")
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button(title.hasPrefix("Edit") ? "Save" : "Create") {
                    submit()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            name = initial.name
            slug = initial.slug
            color = initial.color
            groupName = initial.groupName ?? ""
            slugManuallyEdited = !slug.isEmpty && slug != Project.deriveSlug(from: name)
        }
    }

    private func row<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func submit() {
        var p = initial
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.slug = slug.trimmingCharacters(in: .whitespaces)
        p.color = color
        let group = groupName.trimmingCharacters(in: .whitespaces)
        onSubmit(p, group.isEmpty ? nil : group)
    }
}
