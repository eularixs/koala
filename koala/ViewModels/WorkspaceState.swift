import Foundation
import Observation

// MARK: - RequestTab

struct RequestTab: Identifiable, Hashable {
    let id: UUID
    var request: KoalaRequest
    var response: KoalaResponse? = nil
    var hasUnsavedChanges: Bool = false

    init(id: UUID = UUID(), request: KoalaRequest) {
        self.id = id
        self.request = request
    }
}

// MARK: - WorkspaceState

@MainActor
@Observable
final class WorkspaceState {
    var openTabs: [RequestTab] = []
    var activeTabId: UUID?

    var activeTab: RequestTab? {
        get {
            guard let id = activeTabId else { return nil }
            return openTabs.first(where: { $0.id == id })
        }
        set {
            if let tab = newValue {
                updateTab(tab)
                activeTabId = tab.id
            }
        }
    }

    func openRequest(_ request: KoalaRequest) {
        if let existing = openTabs.first(where: { $0.request.id == request.id }) {
            activeTabId = existing.id
            return
        }
        let tab = RequestTab(request: request)
        openTabs.append(tab)
        activeTabId = tab.id
    }

    func openNew() {
        let tab = RequestTab(request: .empty)
        openTabs.append(tab)
        activeTabId = tab.id
    }

    func closeTab(_ id: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs.remove(at: idx)
        if activeTabId == id {
            activeTabId = neighborId(for: idx)
        }
    }

    func updateTab(_ tab: RequestTab) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        openTabs[idx] = tab
    }

    private func neighborId(for removedIndex: Int) -> UUID? {
        guard !openTabs.isEmpty else { return nil }
        let next = min(removedIndex, openTabs.count - 1)
        return openTabs[next].id
    }
}
