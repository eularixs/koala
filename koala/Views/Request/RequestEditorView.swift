import SwiftUI

// MARK: - RequestEditorTab

enum RequestEditorTab: String, CaseIterable, Identifiable {
    case params  = "Params"
    case headers = "Headers"
    case body    = "Body"
    case auth    = "Auth"
    case mock    = "Mock"

    var id: String { rawValue }
}

// MARK: - RequestEditorView

struct RequestEditorView: View {
    @Binding var tab: RequestTab

    @State private var viewModel = RequestViewModel()
    @State private var selectedRequestEditorTab: RequestEditorTab = .params
    @State private var isResponseHidden: Bool = false
    @State private var showSaveSheet: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(HistoryService.self) private var historyService

    private var environment: KoalaEnvironment? { appState.selectedEnvironment }
    private var globalVariables: [KeyValuePair] { appState.globalVariables }

    var body: some View {
        Group {
            if viewModel.response == nil {
                requestPanel
            } else if isResponseHidden {
                VStack(spacing: 0) {
                    requestPanel
                    Divider()
                    collapsedResponseBar
                }
            } else {
                VSplitView {
                    requestPanel
                        .frame(minHeight: 240, idealHeight: 340)

                    responsePanel
                        .frame(minHeight: 200)
                }
            }
        }
        .onChange(of: viewModel.response) { _, newResponse in
            tab.response = newResponse
            if let response = newResponse {
                historyService.record(
                    request: tab.request,
                    response: response,
                    projectId: appState.activeProjectId ?? UUID()
                )
            }
        }
        .focusedSceneValue(\.requestSaveAction, handleSave)
        .sheet(isPresented: $showSaveSheet) {
            SaveRequestSheet(
                request: tab.request,
                collections: appState.collections,
                onSave: { collectionId, folderId, name in
                    var req = tab.request
                    req.name = name
                    appState.addRequest(
                        parentCollectionId: collectionId,
                        parentFolderId: folderId,
                        request: req
                    )
                    tab.request = req
                    tab.savedSnapshot = req
                }
            )
        }
    }

    // MARK: - Request Panel

    private var requestPanel: some View {
        VStack(spacing: 0) {
            URLBarView(
                request: $tab.request,
                isSending: viewModel.isSending,
                onSend: { sendRequest() }
            )

            Divider()

            requestTabBar

            Divider()

            requestTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var requestTabBar: some View {
        HStack {
            Picker("Request Tab", selection: $selectedRequestEditorTab) {
                ForEach(RequestEditorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            if let err = viewModel.lastError {
                Spacer()
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(err)
            }

            Spacer()

            if viewModel.response != nil {
                Button {
                    isResponseHidden.toggle()
                } label: {
                    Image(systemName: isResponseHidden ? "rectangle.bottomthird.inset.filled" : "rectangle.split.1x2")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isResponseHidden ? "Show response panel" : "Hide response panel")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var collapsedResponseBar: some View {
        Button {
            isResponseHidden = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.caption)
                Text("Show Response")
                    .font(.caption)
                if let response = viewModel.response {
                    Text("·")
                        .foregroundStyle(.secondary)
                    StatusBadgeView(statusCode: response.statusCode)
                    Text("\(response.durationMs) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.05))
    }

    @ViewBuilder
    private var requestTabContent: some View {
        // IMPORTANT: No outer ScrollView here — BodyEditorView hosts an NSScrollView
        // via CodeTextView. Nesting NSScrollView inside SwiftUI ScrollView tears down
        // the ViewBridge (crash). Each editor manages its own scrolling internally.
        switch selectedRequestEditorTab {
        case .params:
            ScrollView {
                ParamsEditorView(request: $tab.request)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        case .headers:
            ScrollView {
                HeadersEditorView(request: $tab.request)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        case .body:
            BodyEditorView(request: $tab.request)
        case .auth:
            ScrollView {
                AuthEditorView(request: $tab.request)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        case .mock:
            ScrollView {
                MockSettingsEditorView(request: $tab.request)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Response Panel

    private var responsePanel: some View {
        ResponseView(
            response: viewModel.response,
            curlCommand: viewModel.curlCommand
        )
    }

    // MARK: - Actions

    private func sendRequest() {
        viewModel.generateCurlCommand(tab.request, environment: environment, globalVariables: globalVariables)
        Task {
            await viewModel.send(tab.request, environment: environment, globalVariables: globalVariables)
        }
    }

    private func handleSave() {
        if appState.request(byId: tab.request.id) != nil {
            appState.updateRequest(tab.request)
            appState.saveActiveProject()
            tab.savedSnapshot = tab.request
        } else {
            showSaveSheet = true
        }
    }
}

// MARK: - SaveRequestSheet

private struct SaveRequestSheet: View {
    let request: KoalaRequest
    let collections: [KoalaCollection]
    let onSave: (_ collectionId: UUID, _ folderId: UUID?, _ name: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameInput: String = ""
    @State private var selectedCollectionId: UUID? = nil
    @State private var selectedFolderId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .frame(minWidth: 440, minHeight: 240)
        .onAppear {
            nameInput = request.name.isEmpty || request.name == "New Request"
                ? defaultName()
                : request.name
            selectedCollectionId = collections.first?.id
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
            Spacer()
            Text("Save Request")
                .font(.headline)
            Spacer()
            Button("Save") {
                guard let cid = selectedCollectionId, !nameInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                onSave(cid, selectedFolderId, nameInput.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCollectionId == nil || nameInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var form: some View {
        if collections.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No collections available")
                    .foregroundStyle(.secondary)
                Text("Create a collection from the sidebar first.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Name") {
                    TextField("Request name", text: $nameInput)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Collection") {
                    Picker("", selection: $selectedCollectionId) {
                        ForEach(collections) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                    }
                    .labelsHidden()
                }
                if let cid = selectedCollectionId,
                   let col = collections.first(where: { $0.id == cid }),
                   !folders(in: col.items).isEmpty {
                    LabeledContent("Folder") {
                        Picker("", selection: $selectedFolderId) {
                            Text("(root)").tag(UUID?.none)
                            ForEach(folders(in: col.items), id: \.id) { f in
                                Text(f.name).tag(Optional(f.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }

    private func folders(in items: [CollectionItem]) -> [Folder] {
        items.compactMap {
            if case .folder(let f) = $0 { return f }
            return nil
        }
    }

    private func defaultName() -> String {
        let url = request.url.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty, let parsed = URL(string: url) {
            return parsed.lastPathComponent.isEmpty ? parsed.host ?? "Untitled" : parsed.lastPathComponent
        }
        return "Untitled"
    }
}

// MARK: - Preview

private struct RequestEditorPreview: View {
    @State private var tab = RequestTab(
        request: KoalaRequest(
            method: .standard(.get),
            url: "https://jsonplaceholder.typicode.com/posts/1",
            headers: [KeyValuePair(key: "Accept", value: "application/json", isEnabled: true)]
        )
    )
    var body: some View {
        RequestEditorView(tab: $tab)
            .environment(AppState())
            .environment(HistoryService())
    }
}

#Preview("RequestEditorView") {
    RequestEditorPreview()
        .frame(width: 800, height: 700)
}
