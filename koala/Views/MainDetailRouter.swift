import SwiftUI

struct MainDetailRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSidebarSection {
        case .mockServers:
            mockServerDetail
        default:
            RequestTabsView { tabBinding in
                RequestEditorView(tab: tabBinding)
            }
        }
    }

    @ViewBuilder
    private var mockServerDetail: some View {
        if let id = appState.selectedMockServerId,
           let server = appState.mockServers.first(where: { $0.id == id }) {
            MockServerDetailView(server: server)
        } else {
            mockServerPlaceholder
        }
    }

    private var mockServerPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Select a Mock Server")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose a server from the sidebar, or create a new one.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
