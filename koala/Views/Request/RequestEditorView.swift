import SwiftUI

// MARK: - RequestEditorTab

private enum RequestEditorTab: String, CaseIterable, Identifiable {
    case params  = "Params"
    case headers = "Headers"
    case body    = "Body"
    case auth    = "Auth"

    var id: String { rawValue }
}

// MARK: - RequestEditorView

struct RequestEditorView: View {
    @Binding var tab: RequestTab

    @State private var viewModel = RequestViewModel()
    @State private var selectedRequestEditorTab: RequestEditorTab = .params
    @State private var saveTask: Task<Void, Never>? = nil

    @Environment(AppState.self) private var appState
    @Environment(HistoryService.self) private var historyService

    private var environment: KoalaEnvironment? { appState.selectedEnvironment }
    private var globalVariables: [KeyValuePair] { appState.globalVariables }

    var body: some View {
        VSplitView {
            requestPanel
                .frame(minHeight: 240, idealHeight: 340)

            responsePanel
                .frame(minHeight: 200)
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
        .onChange(of: tab.request) { _, newRequest in
            scheduleSave(newRequest)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var requestTabContent: some View {
        ScrollView {
            switch selectedRequestEditorTab {
            case .params:  ParamsEditorView(request: $tab.request)
            case .headers: HeadersEditorView(request: $tab.request)
            case .body:    BodyEditorView(request: $tab.request)
            case .auth:    AuthEditorView(request: $tab.request)
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

    private func scheduleSave(_ request: KoalaRequest) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            appState.updateRequest(request)
            appState.saveActiveProject()
        }
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
