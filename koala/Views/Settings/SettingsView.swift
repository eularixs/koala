import SwiftUI

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
                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper(value: $fontSize, in: 10...22, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
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

    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var scopes: String = "read:user read:project create:project delete:project read:deployment create:deployment"
    @State private var saveError: String? = nil
    @State private var savedFlash: Bool = false

    var body: some View {
        Form {
            Section {
                Text("Required to create or deploy Mock Servers. Register an OAuth app at vercel.com/account/integrations and set the redirect URI to:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("koala://oauth/callback")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section("Credentials") {
                TextField("Client ID", text: $clientId, prompt: Text("vercel_oauth_..."))
                    .font(.system(.body, design: .monospaced))
                SecureField("Client Secret", text: $clientSecret, prompt: Text("secret"))
                    .font(.system(.body, design: .monospaced))
                TextField("Scopes", text: $scopes)
                    .font(.system(.caption, design: .monospaced))
            }
            Section {
                HStack {
                    if vercelService.isAuthenticated {
                        Button("Disconnect Vercel", role: .destructive) {
                            try? vercelService.logout()
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
