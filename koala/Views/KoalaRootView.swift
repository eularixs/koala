import SwiftUI

struct KoalaRootView: View {
    @State private var appState = AppState()
    @State private var workspaceState = WorkspaceState()
    @State private var historyService = HistoryService()
    @State private var importExportService = ImportExportService()
    @State private var vercelService = VercelService()
    @State private var mockServerService: MockServerService = MockServerService(vercelService: VercelService())

    @State private var showWelcome: Bool = true
    @State private var loaded: Bool = false

    var body: some View {
        Group {
            if showWelcome {
                WelcomeWindowView(onPicked: { showWelcome = false })
                    .frame(width: 880, height: 560)
            } else {
                MainWindowView(onReturnToWelcome: {
                    showWelcome = true
                })
                .frame(
                    minWidth: 960, idealWidth: 1280, maxWidth: .infinity,
                    minHeight: 600, idealHeight: 800, maxHeight: .infinity
                )
            }
        }
        .environment(appState)
        .environment(workspaceState)
        .environment(historyService)
        .environment(importExportService)
        .environment(vercelService)
        .environment(mockServerService)
        .task {
            guard !loaded else { return }
            appState.loadFromDisk()
            historyService.loadForProject(appState.activeProjectId)
            mockServerService = MockServerService(vercelService: vercelService)
            loaded = true
        }
        .onChange(of: appState.activeProjectId) { _, newId in
            historyService.loadForProject(newId)
        }
        .onOpenURL { url in
            guard url.scheme == "koala" else { return }
            Task { try? await vercelService.handleCallback(url: url) }
        }
    }
}
