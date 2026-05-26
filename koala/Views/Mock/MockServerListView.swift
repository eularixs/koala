import SwiftUI

// MARK: - MockServerListView

struct MockServerListView: View {
    @Environment(AppState.self) private var appState
    @Environment(MockServerService.self) private var mockServerService

    @State private var showingSetup = false
    @State private var renamingId: UUID? = nil
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            serverList
            Divider()
            addButton
        }
        .background(Color.clear)
        .sheet(isPresented: $showingSetup) {
            MockServerSetupView()
        }
        .alert("Rename", isPresented: Binding(
            get: { renamingId != nil },
            set: { if !$0 { renamingId = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renamingId {
                    appState.renameMockServer(id, to: renameText)
                }
                renamingId = nil
            }
            Button("Cancel", role: .cancel) { renamingId = nil }
        }
    }

    // MARK: - List

    private var serverList: some View {
        Group {
            if appState.mockServers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.mockServers) { server in
                            serverRow(server)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No mock servers")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Create one to deploy a live mock API.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func serverRow(_ server: MockServer) -> some View {
        HStack(spacing: 8) {
            // Status dot
            statusDot(server.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.callout)
                    .lineLimit(1)
                if !server.deploymentURL.isEmpty {
                    Text(server.deploymentURL)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !server.deploymentURL.isEmpty {
                Button {
                    copyURL(server.deploymentURL)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy URL")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(appState.selectedMockServerId == server.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .onTapGesture { appState.selectedMockServerId = server.id }
        .contextMenu {
            Button("Rename") {
                renamingId = server.id
                renameText = server.name
            }
            if !server.deploymentURL.isEmpty {
                Button("Copy URL") { copyURL(server.deploymentURL) }
                Button("Open in Browser") {
                    if let url = URL(string: server.deploymentURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { try? await mockServerService.deleteMockServer(server, appState: appState) }
            }
        }
    }

    @ViewBuilder
    private func statusDot(_ status: MockServerStatus) -> some View {
        if status == .deploying {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
        }
    }

    private func statusColor(_ status: MockServerStatus) -> Color {
        switch status {
        case .live:        return .green
        case .deploying:   return .yellow
        case .error:       return .red
        case .notDeployed: return Color.secondary
        }
    }

    // MARK: - Footer

    private var addButton: some View {
        Button {
            showingSetup = true
        } label: {
            Label("New Mock Server", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func copyURL(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}
