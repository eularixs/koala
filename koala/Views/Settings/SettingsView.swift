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
            StorageSettingsTab()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            LicenseTab()
                .tabItem { Label("License", systemImage: "key.fill") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
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
                    HStack(spacing: 6) {
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("", value: $fontSize, in: 10...22, step: 1)
                            .labelsHidden()
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

    @State private var personalToken: String = ""
    @State private var saveError: String? = nil
    @State private var savedFlash: Bool = false

    var body: some View {
        Form {
            Section {
                Text("Connect your own Vercel account. Koala uses it to deploy mock servers and push/pull collaboration bundles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("How to get a token") {
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
                HStack {
                    if vercelService.isAuthenticated {
                        Button("Disconnect Vercel", role: .destructive) {
                            try? vercelService.logout()
                            personalToken = ""
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
        personalToken = vercelService.personalAccessToken ?? ""
    }

    private func save() {
        do {
            try vercelService.setPersonalAccessToken(personalToken)
            savedFlash = true
            saveError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Storage

private struct StorageSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var diskUsage: DiskUsage = .init()
    @State private var pruneDays: Double = 30
    @State private var showPruneConfirm = false
    @State private var clearHistoryDone = false
    @State private var clearRecordingsDone = false

    var body: some View {
        Form {
            Section("Disk Usage") {
                usageRow("History (SQLite)", bytes: diskUsage.sqliteBytes)
                usageRow("Blobs", bytes: diskUsage.blobsBytes)
                usageRow("JSON Data", bytes: diskUsage.jsonBytes)
                usageRow("Total", bytes: diskUsage.total)
                    .fontWeight(.semibold)
            }

            Section("Actions") {
                HStack {
                    Button("Clear History") { clearHistory() }
                        .foregroundStyle(.red)
                    if clearHistoryDone { doneLabel }
                    Spacer()
                }
                HStack {
                    Button("Clear Recordings") { clearRecordings() }
                        .foregroundStyle(.red)
                    if clearRecordingsDone { doneLabel }
                    Spacer()
                }
                Button("Show Storage Folder") { openStorageFolder() }
            }

            Section {
                LabeledContent("Auto-prune history older than") {
                    HStack(spacing: 6) {
                        Text("\(Int(pruneDays)) days")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Slider(value: $pruneDays, in: 7...365, step: 1)
                            .frame(width: 160)
                    }
                }
                Button("Prune Now") { showPruneConfirm = true }
                    .foregroundStyle(.orange)
            } header: {
                Text("Auto-prune")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshUsage() }
        .confirmationDialog(
            "Prune history entries older than \(Int(pruneDays)) days?",
            isPresented: $showPruneConfirm,
            titleVisibility: .visible
        ) {
            Button("Prune", role: .destructive) { pruneHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var doneLabel: some View {
        Label("Done", systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.green)
    }

    private func usageRow(_ label: String, bytes: Int) -> some View {
        LabeledContent(label) {
            Text(formatBytes(bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func clearHistory() {
        guard let pid = appState.activeProjectId else { return }
        Task {
            try? await HistoryRepository().purge(projectId: pid)
            refreshUsage()
            await MainActor.run { clearHistoryDone = true }
        }
    }

    private func clearRecordings() {
        Task {
            let repo = RecordingRepository()
            let sessions = (try? await repo.allSessions()) ?? []
            for s in sessions { try? await repo.deleteSession(id: s.id) }
            refreshUsage()
            await MainActor.run { clearRecordingsDone = true }
        }
    }

    private func pruneHistory() {
        guard let pid = appState.activeProjectId else { return }
        let cutoff = Date().addingTimeInterval(-pruneDays * 86400)
        Task {
            try? await HistoryRepository().prune(projectId: pid, olderThan: cutoff)
            refreshUsage()
        }
    }

    private func openStorageFolder() {
        guard let url = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Koala") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshUsage() {
        Task.detached {
            let usage = DiskUsage.calculate()
            await MainActor.run { diskUsage = usage }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - DiskUsage

private struct DiskUsage {
    var sqliteBytes: Int = 0
    var blobsBytes: Int = 0
    var jsonBytes: Int = 0
    var total: Int { sqliteBytes + blobsBytes + jsonBytes }

    static func calculate() -> DiskUsage {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Koala") else { return .init() }

        return DiskUsage(
            sqliteBytes: dirSize(base, filter: { $0.hasSuffix(".sqlite") || $0.hasSuffix(".sqlite-wal") || $0.hasSuffix(".sqlite-shm") }),
            blobsBytes: dirSize(base.appendingPathComponent("blobs"), filter: { _ in true }),
            jsonBytes: dirSize(base, filter: { $0.hasSuffix(".json") })
        )
    }

    private static func dirSize(_ url: URL, filter: (String) -> Bool) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            guard filter(fileURL.lastPathComponent) else { continue }
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("KoalaLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 80, height: 80)
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
