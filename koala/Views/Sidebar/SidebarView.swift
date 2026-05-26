import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewCollectionSheet = false
    @State private var showingCollabPopover = false

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            Picker("Section", selection: $state.selectedSidebarSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
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
