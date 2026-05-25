import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewCollectionAlert = false
    @State private var newCollectionName = ""

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            ProjectSwitcherView()

            Divider()

            Picker("Section", selection: $state.selectedSidebarSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Label(section.label, systemImage: section.systemImage)
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
                    CollectionTreeView()
                case .environments:
                    EnvironmentListView()
                case .mockServers:
                    Text("Mock Servers — Wave 3")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .history:
                    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.selectedSidebarSection == .collections {
                Divider()
                Button {
                    newCollectionName = ""
                    showingNewCollectionAlert = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .alert("New Collection", isPresented: $showingNewCollectionAlert) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { appState.addCollection(name) }
                appState.saveToDisk()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
