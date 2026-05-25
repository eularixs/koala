import SwiftUI

struct MainWindowView: View {
    @State private var selectedSidebarItem: SidebarSection? = .collections

    var body: some View {
        NavigationSplitView {
            SidebarPlaceholderView(selection: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            RequestPlaceholderView()
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .navigationTitle("Koala")
    }
}

enum SidebarSection: Hashable {
    case collections
    case environments
    case mockServers
    case history
}

private struct SidebarPlaceholderView: View {
    @Binding var selection: SidebarSection?

    var body: some View {
        List(selection: $selection) {
            Section("Workspace") {
                Label("Collections", systemImage: "folder").tag(SidebarSection.collections)
                Label("Environments", systemImage: "leaf").tag(SidebarSection.environments)
                Label("Mock Servers", systemImage: "server.rack").tag(SidebarSection.mockServers)
                Label("History", systemImage: "clock").tag(SidebarSection.history)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct RequestPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "paperplane")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Request Editor")
                .font(.title2)
            Text("Wave 2 will land here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainWindowView()
}
