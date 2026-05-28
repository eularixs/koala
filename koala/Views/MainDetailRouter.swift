import SwiftUI

struct MainDetailRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSidebarSection {
        case .environments:
            environmentDetail
        case .mockServers:
            mockServerDetail
        case .recording:
            if FeatureFlags.proEnabled {
                RecordingDashboardView()
            }
        case .automation:
            if FeatureFlags.proEnabled {
                AutomationDashboardView()
            }
        default:
            RequestTabsView { tabBinding in
                RequestEditorView(tab: tabBinding)
            }
        }
    }

    @ViewBuilder
    private var environmentDetail: some View {
        if let id = appState.environmentDetailId ?? appState.selectedEnvironmentId,
           appState.environments.contains(where: { $0.id == id }) {
            EnvironmentDetailView(environmentId: id)
        } else {
            EnvironmentPlaceholderView()
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
