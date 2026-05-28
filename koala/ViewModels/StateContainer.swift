import Foundation
import Observation

// MARK: - StateContainer
//
// Single-owner of all shared services. Held as @State in koalaApp and injected
// via .environment() on every WindowGroup/Window scene so windows share state.

@MainActor
@Observable
final class StateContainer {
    let appState: AppState
    let workspaceState: WorkspaceState
    let historyService: HistoryService
    let importExportService: ImportExportService
    let vercelService: VercelService
    let mockServerService: MockServerService
    let collaborationService: CollaborationService
    let cookieJar: CookieJarService
    let vaultService: VaultService
    let licenseService: LicenseService
    let automationScheduler: AutomationSchedulerService
    let recordingProxy: RecordingProxyService

    init() {
        let vs = VercelService()
        let app = AppState()
        let cj = CookieJarService()
        let vault = VaultService()
        let license = LicenseService()
        let scheduler = AutomationSchedulerService()
        let recorder = RecordingProxyService()
        // Wire env-deletion → cookie purge hook.
        app.onPurgeCookiesForEnv = { [weak cj] envId in
            cj?.purge(envId: envId)
        }
        // Wire vault service into AppState so callers (e.g. send pipeline)
        // can resolve secrets without touching StateContainer directly.
        app.vaultService = vault
        // Wire automation scheduler's appState resolver so its tick loop can
        // reach collections/envs without holding a strong reference.
        scheduler.appStateResolver = { [weak app] in app }
        appState = app
        workspaceState = WorkspaceState()
        historyService = HistoryService()
        importExportService = ImportExportService()
        vercelService = vs
        mockServerService = MockServerService(vercelService: vs)
        collaborationService = CollaborationService(vercelService: vs)
        cookieJar = cj
        vaultService = vault
        licenseService = license
        automationScheduler = scheduler
        recordingProxy = recorder

        // Boot scheduler tick loop after services are ready.
        scheduler.start()

        // Run one-time JSON→SQLite migration in background.
        Task.detached(priority: .background) {
            await JSONToSQLiteMigrator().migrateIfNeeded()
        }
    }
}
