import SwiftUI
import Sparkle

// MARK: - FocusedValues

struct RequestSaveActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var requestSaveAction: RequestSaveActionKey.Value? {
        get { self[RequestSaveActionKey.self] }
        set { self[RequestSaveActionKey.self] = newValue }
    }
}

@main
struct koalaApp: App {
    @State private var container = StateContainer()
    @FocusedValue(\.requestSaveAction) private var saveAction

    // MARK: Sparkle auto-update
    private let updaterDelegate = SparkleUpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

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
                .environment(container.collaborationService)
                .environment(container.cookieJar)
                .environment(\.vaultService, container.vaultService)
                .environment(\.vaultProjectId, container.appState.activeProjectId)
                .environment(container.licenseService)
                .environment(container.automationScheduler)
                .environment(container.recordingProxy)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    updaterController.updater.checkForUpdates()
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Request") {
                    saveAction?()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(saveAction == nil)
            }
        }

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
                .environment(container.collaborationService)
                .environment(container.cookieJar)
                .environment(\.vaultService, container.vaultService)
                .environment(\.vaultProjectId, container.appState.activeProjectId)
                .environment(container.licenseService)
                .environment(container.automationScheduler)
                .environment(container.recordingProxy)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 880, height: 560)

        // MARK: Settings (native macOS Settings scene, opens via ⌘,)
        Settings {
            SettingsView()
                .environment(container.appState)
                .environment(container.vercelService)
                .environment(container.licenseService)
        }
    }
}
