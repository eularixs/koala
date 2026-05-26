import SwiftUI

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
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .commands {
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
