import SwiftUI

// MARK: - MockServerSetupView

struct MockServerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(MockServerService.self) private var mockServerService

    @State private var serverName: String = ""
    @State private var isCreating = false
    @State private var creationError: String? = nil

    private var defaultName: String {
        guard let project = appState.activeProject else { return "Mock Server" }
        return "\(project.slug) mock"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formContent
                .padding(20)
            Spacer()
            if let err = creationError {
                Divider()
                errorBanner(err)
            }
        }
        .frame(width: 460)
        .frame(minHeight: 340)
        .onAppear {
            if serverName.isEmpty { serverName = defaultName }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Mock Server")
                    .font(.headline)
                Text("Deploy a live mock API on Vercel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCreating {
                ProgressView()
                    .scaleEffect(0.75)
                    .padding(.trailing, 4)
            }
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.escape)
            Button("Create") { createServer() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(serverName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Server Name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. eularix mock", text: $serverName)
                    .textFieldStyle(.roundedBorder)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What happens next", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        infoBullet("Your browser will open for Vercel OAuth (first time only).")
                        infoBullet("A dedicated Vercel project is created for this mock server.")
                        infoBullet("A Next.js app is deployed — this takes ~1 minute.")
                        infoBullet("You can add endpoints once deployment is complete.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.05))
    }

    private func createServer() {
        guard let project = appState.activeProject else { return }
        let name = serverName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreating = true
        creationError = nil

        Task {
            do {
                _ = try await mockServerService.createMockServer(name: name, project: project, appState: appState)
                dismiss()
            } catch {
                creationError = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#Preview {
    MockServerSetupView()
        .environment(AppState())
}
