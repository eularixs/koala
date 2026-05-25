import SwiftUI

struct MainWindowView: View {
    @State private var appState = AppState()
    @State private var requestViewModel = RequestViewModel()
    @State private var workspaceState = WorkspaceState()
    @State private var historyService = HistoryService()

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            RequestEditorView(viewModel: requestViewModel)
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .navigationTitle("Koala")
        .environment(appState)
        .environment(workspaceState)
        .environment(historyService)
        .task {
            appState.loadFromDisk()
            historyService.load()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                environmentMenu
            }
        }
    }

    private var environmentMenu: some View {
        Menu {
            Button("No Environment") {
                appState.selectedEnvironmentId = nil
            }
            if !appState.environments.isEmpty {
                Divider()
                ForEach(appState.environments) { env in
                    Button {
                        appState.selectedEnvironmentId = env.id
                    } label: {
                        HStack {
                            Text(env.name)
                            if appState.selectedEnvironmentId == env.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Manage Environments...") {
                appState.selectedSidebarSection = .environments
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "leaf")
                Text(appState.selectedEnvironment?.name ?? "No Environment")
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .font(.callout)
        }
        .help("Select active environment")
    }
}

#Preview {
    MainWindowView()
}
