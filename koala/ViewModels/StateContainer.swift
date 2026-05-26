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

    init() {
        let vs = VercelService()
        appState = AppState()
        workspaceState = WorkspaceState()
        historyService = HistoryService()
        importExportService = ImportExportService()
        vercelService = vs
        mockServerService = MockServerService(vercelService: vs)
        collaborationService = CollaborationService(vercelService: vs)
    }
}
