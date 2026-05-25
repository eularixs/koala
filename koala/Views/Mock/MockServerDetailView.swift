import SwiftUI

// MARK: - MockServerDetailView

struct MockServerDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(MockServerService.self) private var mockServerService

    var server: MockServer

    @State private var showingDeleteAlert = false
    @State private var showingEndpointEditor = false
    @State private var editingEndpoint: MockEndpoint? = nil
    @State private var isSavingEndpoints = false
    @State private var savingError: String? = nil
    @State private var lastSyncDate: Date? = nil
    @State private var isDeploying = false
    @State private var deployError: String? = nil

    private var mutableServer: MockServer {
        appState.mockServers.first(where: { $0.id == server.id }) ?? server
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            urlPill
            Divider()
            endpointList
            Divider()
            bottomBar
        }
        .sheet(isPresented: $showingEndpointEditor) {
            if let ep = editingEndpoint {
                MockEndpointEditorView(endpoint: ep) { saved in
                    upsertEndpoint(saved)
                }
            }
        }
        .alert("Delete Mock Server", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) { deleteServer() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the Vercel project and all endpoint configurations. This cannot be undone.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(mutableServer.name)
                    .font(.headline)
                DeploymentStatusView(status: mutableServer.status, lastDeployedAt: lastSyncDate)
            }
            Spacer()
            if !mutableServer.deploymentURL.isEmpty {
                Button {
                    copyURL()
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openInBrowser()
                } label: {
                    Label("Open", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                Task { await deployServer() }
            } label: {
                Label(isDeploying ? "Deploying..." : "Deploy", systemImage: "paperplane")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDeploying)

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - URL Pill

    private var urlPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(mutableServer.deploymentURL.isEmpty ? "Not yet deployed" : mutableServer.deploymentURL)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(mutableServer.deploymentURL.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Endpoint List

    private var endpointList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Endpoints")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingEndpoint = MockEndpoint.empty
                    showingEndpointEditor = true
                } label: {
                    Label("Add Endpoint", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if mutableServer.endpoints.isEmpty {
                emptyEndpointsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(mutableServer.endpoints) { endpoint in
                            endpointRow(endpoint)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyEndpointsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("No endpoints yet")
                .foregroundStyle(.secondary)
            Text("Add an endpoint to start mocking API responses.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func endpointRow(_ endpoint: MockEndpoint) -> some View {
        HStack(spacing: 12) {
            Text(endpoint.method.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(endpoint.method.color)
                .frame(width: 56, alignment: .leading)

            Text(endpoint.path)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(endpoint.isEnabled ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            Text(endpoint.responseMode.displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)

            Toggle("", isOn: Binding(
                get: { endpoint.isEnabled },
                set: { val in toggleEndpoint(endpoint.id, enabled: val) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Button {
                editingEndpoint = endpoint
                showingEndpointEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button(role: .destructive) {
                deleteEndpoint(endpoint.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if let err = savingError ?? deployError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await saveAllToVercel() }
            } label: {
                Label(isSavingEndpoints ? "Saving..." : "Save All to Vercel", systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingEndpoints || mutableServer.endpoints.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func upsertEndpoint(_ ep: MockEndpoint) {
        var updated = mutableServer
        if let idx = updated.endpoints.firstIndex(where: { $0.id == ep.id }) {
            updated.endpoints[idx] = ep
        } else {
            updated.endpoints.append(ep)
        }
        appState.updateMockServer(updated)
    }

    private func deleteEndpoint(_ id: UUID) {
        var updated = mutableServer
        updated.endpoints.removeAll(where: { $0.id == id })
        appState.updateMockServer(updated)
    }

    private func toggleEndpoint(_ id: UUID, enabled: Bool) {
        var updated = mutableServer
        if let idx = updated.endpoints.firstIndex(where: { $0.id == id }) {
            updated.endpoints[idx].isEnabled = enabled
        }
        appState.updateMockServer(updated)
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mutableServer.deploymentURL, forType: .string)
    }

    private func openInBrowser() {
        guard let url = URL(string: mutableServer.deploymentURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func deleteServer() {
        Task {
            try? await mockServerService.deleteMockServer(mutableServer, appState: appState)
        }
    }

    private func deployServer() async {
        isDeploying = true
        deployError = nil
        defer { isDeploying = false }
        do {
            try await mockServerService.deployServer(mutableServer)
        } catch {
            deployError = error.localizedDescription
        }
    }

    private func saveAllToVercel() async {
        isSavingEndpoints = true
        savingError = nil
        defer { isSavingEndpoints = false }
        do {
            try await mockServerService.saveAllEndpoints(server: mutableServer)
            lastSyncDate = Date()
        } catch {
            savingError = error.localizedDescription
        }
    }
}
