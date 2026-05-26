import SwiftUI
import AppKit

// MARK: - SettingsView (native macOS Settings scene tabs)

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            VercelSettingsTab()
                .tabItem { Label("Vercel", systemImage: "cloud") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("EditorFontSize") private var fontSize: Double = 13
    @AppStorage("EditorFontFamily") private var fontFamily: String = "Monaco"
    @AppStorage("EditorTabSize") private var tabSize: Int = 2
    @AppStorage("PreferDarkMode") private var preferDarkMode: Bool = false
    @AppStorage("ShowResponseTimeline") private var showTimeline: Bool = true

    private let fontFamilies = [
        "Monaco", "Menlo", "SF Mono", "Courier New", "Andale Mono"
    ]

    var body: some View {
        Form {
            Section("Code Editor") {
                Picker("Font Family", selection: $fontFamily) {
                    ForEach(fontFamilies, id: \.self) { f in
                        Text(f).tag(f).font(.custom(f, size: 13))
                    }
                }
                LabeledContent("Font Size") {
                    Stepper(value: $fontSize, in: 10...22, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                    }
                    .labelsHidden()
                }
                Picker("Tab Size", selection: $tabSize) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
            }
            Section("Appearance") {
                Toggle("Always prefer dark mode", isOn: $preferDarkMode)
            }
            Section("Response") {
                Toggle("Show timeline tab", isOn: $showTimeline)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Vercel

private struct VercelSettingsTab: View {
    @Environment(VercelService.self) private var vercelService

    @State private var personalToken: String = ""
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var scopes: String = "read:user read:project create:project delete:project read:deployment create:deployment"
    @State private var saveError: String? = nil
    @State private var savedFlash: Bool = false
    @State private var showAdvanced: Bool = false

    var body: some View {
        Form {
            Section {
                Text("Connect your own Vercel account. Koala uses it to deploy mock servers and push/pull collaboration bundles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("How to get a token (recommended)") {
                stepRow(1, "Open Vercel tokens page:") {
                    linkButton("vercel.com/account/tokens", url: "https://vercel.com/account/tokens")
                }
                stepRow(2, "Click \"Create Token\".") { EmptyView() }
                stepRow(3, "Name: \"Koala\". Scope: Full Account. Expiration: your choice.") { EmptyView() }
                stepRow(4, "Copy the token (Vercel shows it ONCE) → paste below.") { EmptyView() }
            }

            Section("Personal Access Token") {
                SecureField("Token", text: $personalToken, prompt: Text("vercel_..."))
                    .font(.system(.body, design: .monospaced))
                Text("Stored securely in macOS Keychain. Used as Bearer for all Vercel API calls.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Only use if distributing Koala to others under your OAuth app. Most users should use the token above instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Redirect URL to register on Vercel integration:")
                            .font(.caption)
                        Text("koala://oauth/callback")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                        TextField("Client ID", text: $clientId, prompt: Text("vercel_oauth_..."))
                            .font(.system(.body, design: .monospaced))
                        SecureField("Client Secret", text: $clientSecret, prompt: Text("secret"))
                            .font(.system(.body, design: .monospaced))
                        TextField("Scopes", text: $scopes)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Advanced: OAuth Integration", systemImage: "gearshape.2")
                        .font(.caption)
                }
            }

            Section {
                HStack {
                    if vercelService.isAuthenticated {
                        Button("Disconnect Vercel", role: .destructive) {
                            try? vercelService.logout()
                            personalToken = ""
                            clientId = ""
                            clientSecret = ""
                        }
                    }
                    Spacer()
                    if savedFlash {
                        Label("Saved", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let err = saveError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { load() }
    }

    @ViewBuilder
    private func stepRow<Trailing: View>(_ step: Int, _ text: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.caption)
                trailing()
            }
            Spacer(minLength: 0)
        }
    }

    private func linkButton(_ label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func load() {
        clientId = UserDefaults.standard.string(forKey: "VercelClientId") ?? ""
        scopes = UserDefaults.standard.string(forKey: "VercelOAuthScopes") ?? scopes
        clientSecret = (try? KeychainService().string(for: "vercel.oauth.clientSecret")) ?? ""
        personalToken = vercelService.personalAccessToken ?? ""
        if !clientId.isEmpty || !clientSecret.isEmpty { showAdvanced = true }
    }

    private func save() {
        do {
            UserDefaults.standard.set(clientId, forKey: "VercelClientId")
            UserDefaults.standard.set(scopes, forKey: "VercelOAuthScopes")
            try KeychainService().set(clientSecret, for: "vercel.oauth.clientSecret")
            try vercelService.setPersonalAccessToken(personalToken)
            savedFlash = true
            saveError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Koala")
                .font(.title2.weight(.semibold))
            Text("Native macOS API client")
                .foregroundStyle(.secondary)
            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
