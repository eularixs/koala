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
    @Bindable var viewModel: RequestViewModel

    @State private var selectedRequestEditorTab: RequestEditorTab = .params
    @State private var environment: KoalaEnvironment? = nil
    @State private var globalVariables: [KeyValuePair] = []

    var body: some View {
        VSplitView {
            requestPanel
                .frame(minHeight: 240, idealHeight: 340)

            responsePanel
                .frame(minHeight: 200)
        }
    }

    // MARK: - Request Panel

    private var requestPanel: some View {
        VStack(spacing: 0) {
            URLBarView(
                request: $viewModel.request,
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
            case .params:  ParamsEditorView(request: $viewModel.request)
            case .headers: HeadersEditorView(request: $viewModel.request)
            case .body:    BodyEditorView(request: $viewModel.request)
            case .auth:    AuthEditorView(request: $viewModel.request)
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
        viewModel.generateCurlCommand(environment: environment, globalVariables: globalVariables)
        Task {
            await viewModel.send(environment: environment, globalVariables: globalVariables)
        }
    }
}

// MARK: - Preview

#Preview("RequestEditorView") {
    let vm = RequestViewModel(
        request: KoalaRequest(
            method: .standard(.get),
            url: "https://jsonplaceholder.typicode.com/posts/1",
            headers: [KeyValuePair(key: "Accept", value: "application/json", isEnabled: true)]
        )
    )

    return RequestEditorView(viewModel: vm)
        .frame(width: 800, height: 700)
}
