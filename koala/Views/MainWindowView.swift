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

    // MARK: Settings
    @State private var showSettings = false

    // MARK: Project Popover
    @State private var showProjectPopover = false

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
                projectMenu
            }
            ToolbarItem(placement: .navigation) {
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Project Menu (gear icon → popover with search)

    private var projectMenu: some View {
        Button {
            showProjectPopover.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.body)
        }
        .buttonStyle(.plain)
        .help("Manage projects")
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

    // MARK: - Environment Menu

    private var environmentMenu: some View {
        Menu {
            Button("No Environment") {
                appState.selectedEnvironmentId = nil
            }
            if !appState.environments.isEmpty {
                Divider()
                ForEach(appState.environments) { env in
                    Button {
                        appState.selectedEnvironmentId = env.id
                    } label: {
                        HStack {
                            if let hex = env.color, let col = Color(hex: hex) {
                                Circle().fill(col).frame(width: 10, height: 10)
                            }
                            Text(env.name)
                            if appState.selectedEnvironmentId == env.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Manage Environments...") {
                appState.selectedSidebarSection = .environments
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "leaf")
                if let hex = appState.selectedEnvironment?.color, let col = Color(hex: hex) {
                    Circle().fill(col).frame(width: 9, height: 9)
                }
            }
            .font(.callout)
        }
        .menuIndicator(.hidden)
        .help(appState.selectedEnvironment?.name ?? "No environment selected")
    }

    // MARK: - File Menu

    private var fileMenu: some View {
        Menu {
            Button("Import...") {
                showImporter = true
            }
            Menu("Export Active Collection...") {
                Button("Postman v2.1") { beginExport(.postman) }
                Button("OpenAPI 3.0") { beginExport(.openapi) }
                Button("Markdown") { beginExport(.markdown) }
                Button("Koala Native") { beginExport(.koalaNative) }
            }
            .disabled(appState.collections.isEmpty)
            Divider()
            Button {
                showSettings = true
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
        } label: {
            Label("File", systemImage: "doc")
        }
        .help("Import, export, settings")
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
        .frame(width: 280)
        .frame(maxHeight: 320)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search projects", text: $search)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
        Button {
            appState.switchProject(to: project.id)
            showProjectPopover = false
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: project.color ?? "") ?? .secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(project.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if appState.activeProjectId == project.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
