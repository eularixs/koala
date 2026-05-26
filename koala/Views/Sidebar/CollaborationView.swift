import SwiftUI

// MARK: - CollaborationView

/// Push / Pull controls for syncing the active project's collections, environments,
/// and global variables to Vercel Edge Config.
struct CollaborationView: View {
    @Environment(AppState.self) private var appState
    @Environment(CollaborationService.self) private var collab
    @Environment(\.dismiss) private var dismiss

    @State private var showPullConfirm = false
    @State private var generatedKey: String? = nil
    @State private var keyGenError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            statusCard

            HStack(spacing: 8) {
                Button {
                    Task { await push() }
                } label: {
                    Label("Push", systemImage: "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(disabled)

                Button {
                    showPullConfirm = true
                } label: {
                    Label("Pull", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(disabled || appState.activeProject?.collabEdgeConfigId == nil)
            }

            if let err = collab.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider().padding(.vertical, 2)

            Text("Share with teammates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                Task { await generateKey() }
            } label: {
                Label("Generate Share Key", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(disabled || appState.activeProject?.collabEdgeConfigId == nil)

            if let key = generatedKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share key (paste into teammate's Welcome → Join Project):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(key)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(key, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let err = keyGenError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 360)
        .alert("Pull from Vercel?", isPresented: $showPullConfirm) {
            Button("Pull & Replace", role: .destructive) {
                Task { await pull() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces local collections, environments, and global variables for the current project with the latest pushed snapshot.")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.tint)
            Text("Collaboration")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let project = appState.activeProject {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                if let id = project.collabEdgeConfigId {
                    Text("Linked: \(id)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Not linked yet. Push to create a store.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active project")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if collab.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let date = collab.lastSyncDate {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Last sync: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Never synced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private var disabled: Bool {
        appState.activeProjectId == nil || collab.isSyncing
    }

    private func generateKey() async {
        guard let pid = appState.activeProjectId else { return }
        keyGenError = nil
        do {
            generatedKey = try await collab.generateShareKey(projectId: pid, appState: appState)
        } catch {
            keyGenError = error.localizedDescription
        }
    }

    private func push() async {
        guard let id = appState.activeProjectId else { return }
        try? await collab.pushProject(projectId: id, appState: appState)
    }

    private func pull() async {
        guard let id = appState.activeProjectId else { return }
        try? await collab.pullProject(projectId: id, appState: appState)
    }
}
