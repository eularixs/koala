import SwiftUI

@main
struct koalaApp: App {
    @State private var container = StateContainer()

    var body: some Scene {
        // MARK: Main Window
        WindowGroup {
            KoalaRootView()
                .environment(container.appState)
                .environment(container.workspaceState)
                .environment(container.historyService)
                .environment(container.importExportService)
                .environment(container.vercelService)
                .environment(container.mockServerService)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)

        // MARK: Welcome / Manage Projects Window
        Window("Projects", id: "welcome") {
            WelcomeWindowView(onPicked: { _ in })
                .frame(width: 880, height: 560)
                .environment(container.appState)
                .environment(container.workspaceState)
                .environment(container.historyService)
                .environment(container.importExportService)
                .environment(container.vercelService)
                .environment(container.mockServerService)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 880, height: 560)

        // MARK: Settings (native macOS Settings scene, opens via ⌘,)
        Settings {
            SettingsView()
                .environment(container.appState)
                .environment(container.vercelService)
        }
    }
}
