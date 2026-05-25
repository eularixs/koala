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

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            MainDetailRouter()
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .navigationTitle(appState.activeProject?.name ?? "Koala")
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
    }

    // MARK: - Project Menu

    private var projectMenu: some View {
        Menu {
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
            Divider()
            Button("Back to Welcome...") {
                onReturnToWelcome()
            }
        } label: {
            HStack(spacing: 6) {
                if let hex = appState.activeProject?.color, let col = Color(hex: hex) {
                    Circle().fill(col).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "square.stack.3d.up")
                }
                Text(appState.activeProject?.name ?? "No Project")
                    .frame(maxWidth: 160, alignment: .leading)
                    .lineLimit(1)
            }
            .font(.callout)
        }
        .help("Switch project")
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
                Text(appState.selectedEnvironment?.name ?? "No Environment")
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .font(.callout)
        }
        .help("Select active environment")
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
        } label: {
            Label("File", systemImage: "doc")
        }
        .help("Import or export collections")
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
