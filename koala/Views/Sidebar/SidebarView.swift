import SwiftUI

/// Sidebar placeholder for the Recording section — the full dashboard lives
/// in the detail pane (see `MainDetailRouter`). The sidebar just shows an
/// informational stub so the section switch has content of its own.
private struct RecordingSidebarStub: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Recording Proxy")
                .font(.callout.weight(.semibold))
            Text("Open the detail pane to start the proxy and view captures.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sidebar stub for the Automation section. The dashboard lives in the detail
/// pane (see `MainDetailRouter`). Mirrors the Recording stub pattern.
private struct AutomationSidebarStub: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Automation")
                .font(.callout.weight(.semibold))
            Text("Open the detail pane to manage scheduled collection runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewCollectionSheet = false
    @State private var showingCollabPopover = false

    private var visibleSections: [SidebarSection] {
        SidebarSection.allCases.filter { section in
            switch section {
            case .recording, .automation:
                return FeatureFlags.proEnabled
            default:
                return true
            }
        }
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            Picker("Section", selection: $state.selectedSidebarSection) {
                ForEach(visibleSections, id: \.self) { section in
                    Image(systemName: section.systemImage)
                        .help(section.label)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            Group {
                switch appState.selectedSidebarSection {
                case .collections:
                    CollectionTreeView(onRequestNew: {
                        showingNewCollectionSheet = true
                    })
                case .environments:
                    EnvironmentListView()
                case .mockServers:
                    MockServerListView()
                case .history:
                    HistoryView()
                case .recording:
                    RecordingSidebarStub()
                case .automation:
                    AutomationSidebarStub()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCollabPopover.toggle()
                } label: {
                    Image(systemName: "person.2")
                }
                .help("Collaboration (Push / Pull)")
                .popover(isPresented: $showingCollabPopover, arrowEdge: .bottom) {
                    CollaborationView()
                        .environment(appState)
                }
            }
        }
        .sheet(isPresented: $showingNewCollectionSheet) {
            CollectionEditorSheet(editing: nil) { name, colorHex in
                appState.addCollection(name)
                if let hex = colorHex, let last = appState.collections.last {
                    var c = last
                    c.color = hex
                    if let idx = appState.collections.firstIndex(where: { $0.id == last.id }) {
                        appState.collections[idx] = c
                    }
                }
                appState.saveToDisk()
            }
        }
    }
}
