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

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            MainDetailRouter()
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
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

    // MARK: - Project Menu (gear icon "Manage Projects")

    private var projectMenu: some View {
        Menu {
            Section("Switch Project") {
                ForEach(appState.projects) { project in
                    Button {
                        appState.switchProject(to: project.id)
                    } label: {
                        HStack {
                            if let hex = project.color, let col = Color(hex: hex) {
                                Circle().fill(col).frame(width: 10, height: 10)
                            }
                            Text(project.name)
                            if appState.activeProjectId == project.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                onReturnToWelcome()
            } label: {
                Label("Manage Projects", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.body)
        }
        .menuIndicator(.hidden)
        .help("Manage projects")
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
