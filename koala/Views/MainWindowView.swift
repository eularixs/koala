import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportExportService.self) private var importExportService

    let onReturnToWelcome: () -> Void

    // MARK: Import state
    @State private var showImporter = false
    @State private var importError: String? = nil
    @State private var showImportError = false

    // MARK: Export state
    @State private var exportFormat: ExportFormat? = nil
    @State private var showExporter = false
    @State private var exportDocument: KoalaExportDocument? = nil
    @State private var exportFilename: String = "export"

    // MARK: Project Popover
    @State private var showProjectPopover = false

    // MARK: Environment Popover
    @State private var showEnvPopover = false

    // MARK: Search
    @State private var showSearchSheet = false
    @State private var showGlobalSearchSheet = false

    // MARK: Collaboration Popover
    @State private var showCollabPopover = false

    // MARK: Tag Manager
    @State private var showTagManager = false
    @State private var showTagPicker = false

    // MARK: Rename Popover
    @State private var showRenamePopover = false
    @State private var renameBuffer: String = ""

    @Environment(WorkspaceState.self) private var workspaceState

    // MARK: openWindow environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            MainDetailRouter()
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .background(
            WindowConfigurator(
                hideMinimize: false,
                hideZoom: false,
                resizable: true,
                minSize: NSSize(width: 960, height: 600),
                maxSize: nil
            )
        )
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                projectIconButton
            }
            ToolbarItem(placement: .principal) {
                projectNameButton
            }
            ToolbarItem(placement: .primaryAction) {
                searchButton
            }
            ToolbarItem(placement: .primaryAction) {
                newTabButton
            }
            ToolbarItem(placement: .primaryAction) {
                environmentMenu
            }
            ToolbarItem(placement: .primaryAction) {
                fileMenu
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .alert("Import Error", isPresented: $showImportError, presenting: importError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error)
        }
        .sheet(isPresented: $showSearchSheet) {
            SearchRequestsSheet { request in
                workspaceState.openRequest(request)
            }
            .environment(appState)
        }
        .sheet(isPresented: $showGlobalSearchSheet) {
            GlobalSearchSheet { project, request in
                appState.switchProject(to: project.id)
                workspaceState.openRequest(request)
                showGlobalSearchSheet = false
            }
            .environment(appState)
            .environment(workspaceState)
        }
        .background(
            Button("") { showGlobalSearchSheet = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .hidden()
        )
        .sheet(isPresented: $showTagManager) {
            TagManagerSheet()
                .environment(appState)
        }
    }

    // MARK: - New Tab + Search Buttons

    private var newTabButton: some View {
        Button {
            workspaceState.openNew()
        } label: {
            Image(systemName: "plus.square")
                .font(.body)
        }
        .help("New Request Tab (⌘T)")
    }

    private var searchButton: some View {
        Button {
            showSearchSheet = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body)
        }
        .help("Search requests (⌘F)")
        .keyboardShortcut("f", modifiers: .command)
    }

    // MARK: - Project Icon (left) + Project Name (center)

    private var projectIconButton: some View {
        Button {
            showProjectPopover.toggle()
        } label: {
            Image(systemName: "network")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch project")
        .popover(isPresented: $showProjectPopover, arrowEdge: .bottom) {
            ProjectSwitcherPopover(
                showProjectPopover: $showProjectPopover,
                onManageProjects: {
                    showProjectPopover = false
                    openWindow(id: "welcome")
                }
            )
            .environment(appState)
        }
    }

    private var projectNameButton: some View {
        HStack(spacing: 8) {
            Button {
                renameBuffer = appState.activeProject?.name ?? ""
                showRenamePopover.toggle()
            } label: {
                Text(appState.activeProject?.name ?? "No Project")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRenamePopover, arrowEdge: .bottom) {
                renamePopover
            }
            tagChip
        }
    }

    private var renamePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename Project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Project name", text: $renameBuffer)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button("Cancel") { showRenamePopover = false }
                Button("Save") { commitRename() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameBuffer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func commitRename() {
        guard let pid = appState.activeProjectId else { return }
        let trimmed = renameBuffer.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.renameProject(pid, to: trimmed)
        showRenamePopover = false
    }

    @ViewBuilder
    private var tagChip: some View {
        Button {
            showTagPicker.toggle()
        } label: {
            TagBadgeView(tag: appState.tag(byId: appState.activeProject?.tagId))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                tagPickerRow(label: "No Tag", color: .secondary) {
                    if let pid = appState.activeProjectId { appState.setTag(nil, for: pid) }
                    showTagPicker = false
                }
                Divider()
                ForEach(appState.tags) { t in
                    tagPickerRow(label: t.name, color: Color(hex: t.colorHex) ?? .gray) {
                        if let pid = appState.activeProjectId { appState.setTag(t.id, for: pid) }
                        showTagPicker = false
                    }
                }
                Divider()
                Button {
                    showTagPicker = false
                    showTagManager = true
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Manage Tags...")
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 200)
            .padding(.vertical, 4)
        }
    }

    private func tagPickerRow(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    // MARK: - Environment Menu

    private var environmentMenu: some View {
        Button {
            showEnvPopover.toggle()
        } label: {
            envIconLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: appState.selectedEnvironment?.name ?? "No environment selected"))
        .popover(isPresented: $showEnvPopover, arrowEdge: .bottom) {
            EnvironmentPickerPopover(
                showEnvPopover: $showEnvPopover,
                onManageEnvironments: {
                    showEnvPopover = false
                    appState.selectedSidebarSection = .environments
                }
            )
            .environment(appState)
        }
    }

    @ViewBuilder
    private var envIconLabel: some View {
        if let env = appState.selectedEnvironment {
            let color = (env.color.flatMap { Color(hex: $0) }) ?? .accentColor
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(env.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "leaf")
                    .font(.caption)
                Text("No env")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Color.secondary.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.20), lineWidth: 0.5))
        }
    }

    // MARK: - File Menu

    private var fileMenu: some View {
        Menu {
            Button {
                showImporter = true
            } label: {
                Label("Import...", systemImage: "square.and.arrow.down")
            }
            Menu {
                Button("Postman v2.1") { beginExport(.postman) }
                Button("OpenAPI 3.0") { beginExport(.openapi) }
                Button("HAR 1.2") { beginExport(.har) }
                Button("Markdown") { beginExport(.markdown) }
                Button("Koala Native") { beginExport(.koalaNative) }
            } label: {
                Label("Export Active Collection...", systemImage: "square.and.arrow.up")
            }
            .disabled(appState.collections.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuIndicator(.hidden)
        .help("Import / export")
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
            showImportError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try importExportService.importFile(
                    at: url,
                    into: appState.activeProjectId ?? UUID(),
                    appState: appState
                )
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }

    // MARK: - Export

    private func beginExport(_ format: ExportFormat) {
        guard let collection = appState.collections.first else { return }
        do {
            let (data, string, ext) = try importExportService.exportCollectionPayload(collection, as: format)
            let bytes = data ?? Data((string ?? "").utf8)
            exportDocument = KoalaExportDocument(data: bytes)
            exportFormat = format
            exportFilename = "\(collection.name).\(ext)"
            showExporter = true
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    private var exportContentType: UTType {
        switch exportFormat {
        case .markdown: return .plainText
        case .har: return .json
        default: return .json
        }
    }
}

// MARK: - ProjectSwitcherPopover

private struct ProjectSwitcherPopover: View {
    @Environment(AppState.self) private var appState
    @Binding var showProjectPopover: Bool
    let onManageProjects: () -> Void

    @State private var search: String = ""

    private var filtered: [Project] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return appState.projects }
        return appState.projects.filter {
            $0.name.lowercased().contains(needle) || $0.slug.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            projectList
            Divider()
            manageRow
        }
        .frame(width: 460)
        .frame(minHeight: 420, maxHeight: 580)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)
            TextField("Search projects", text: $search)
                .textFieldStyle(.plain)
                .font(.body)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { project in
                    projectRow(project)
                    if project.id != filtered.last?.id {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let isSelected = appState.activeProjectId == project.id
        return Button {
            appState.switchProject(to: project.id)
            showProjectPopover = false
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: project.color ?? "") ?? .secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(project.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var manageRow: some View {
        Button(action: onManageProjects) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Manage Projects")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EnvironmentPickerPopover

private struct EnvironmentPickerPopover: View {
    @Environment(AppState.self) private var appState
    @Binding var showEnvPopover: Bool
    let onManageEnvironments: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            envList
            Divider()
            manageRow
        }
        .frame(width: 340)
        .frame(minHeight: 360, maxHeight: 520)
    }

    private var envList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                noEnvRow
                if !appState.environments.isEmpty {
                    Divider().padding(.leading, 32)
                    ForEach(appState.environments) { env in
                        envRow(env)
                        if env.id != appState.environments.last?.id {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    private var noEnvRow: some View {
        let isSelected = appState.selectedEnvironmentId == nil
        return Button {
            appState.selectedEnvironmentId = nil
            showEnvPopover = false
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    .frame(width: 10, height: 10)
                Text("No Environment")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func envRow(_ env: KoalaEnvironment) -> some View {
        let isSelected = appState.selectedEnvironmentId == env.id
        let color = (env.color.flatMap { Color(hex: $0) }) ?? .secondary
        return Button {
            appState.selectedEnvironmentId = env.id
            showEnvPopover = false
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(env.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if env.name.lowercased() == "default" {
                    Text("default")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? color.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var manageRow: some View {
        Button(action: onManageEnvironments) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Manage Environments")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - KoalaExportDocument (FileDocument for fileExporter)

struct KoalaExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText, .data] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
