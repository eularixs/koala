import SwiftUI

struct KoalaRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(HistoryService.self) private var historyService
    @Environment(VercelService.self) private var vercelService
    @Environment(MockServerService.self) private var mockServerService

    @Environment(\.openWindow) private var openWindow

    @State private var loaded: Bool = false

    var body: some View {
        MainWindowView(onReturnToWelcome: {
            openWindow(id: "welcome")
        })
        .frame(
            minWidth: 960, idealWidth: 1280, maxWidth: .infinity,
            minHeight: 600, idealHeight: 800, maxHeight: .infinity
        )
        .task {
            guard !loaded else { return }
            appState.loadFromDisk()
            historyService.loadForProject(appState.activeProjectId)
            loaded = true

            // If no projects exist after loading, open the welcome window
            if appState.projects.isEmpty {
                openWindow(id: "welcome")
            }
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
