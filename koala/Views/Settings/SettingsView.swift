import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VercelService.self) private var vercelService

    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var scopes: String = "read:user read:project create:project delete:project read:deployment create:deployment"
    @State private var saveError: String? = nil
    @State private var savedFlash: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title3.weight(.semibold))

            Text("Vercel OAuth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Required to create or deploy Mock Servers. Register a Vercel OAuth app at vercel.com/account/integrations and set the redirect URI to:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("koala://oauth/callback")
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 12) {
                row("Client ID") {
                    TextField("", text: $clientId, prompt: Text("vercel_oauth_..."))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                }
                Divider()
                row("Client Secret") {
                    SecureField("", text: $clientSecret, prompt: Text("secret"))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                }
                Divider()
                row("Scopes") {
                    TextField("", text: $scopes, prompt: Text("read:user read:project ..."))
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if savedFlash {
                Label("Saved", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                if vercelService.isAuthenticated {
                    Button("Disconnect Vercel", role: .destructive) {
                        try? vercelService.logout()
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { load() }
    }

    private func row<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() {
        clientId = UserDefaults.standard.string(forKey: "VercelClientId") ?? ""
        scopes = UserDefaults.standard.string(forKey: "VercelOAuthScopes") ?? scopes
        clientSecret = (try? KeychainService().string(for: "vercel.oauth.clientSecret")) ?? ""
    }

    private func save() {
        do {
            UserDefaults.standard.set(clientId, forKey: "VercelClientId")
            UserDefaults.standard.set(scopes, forKey: "VercelOAuthScopes")
            try KeychainService().set(clientSecret, for: "vercel.oauth.clientSecret")
            savedFlash = true
            saveError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
