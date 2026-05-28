import SwiftUI
import UniformTypeIdentifiers
import Observation

// MARK: - CAManaging protocol
//
// UI contract for the root CA service. KoalaRootCA will conform once
// the swift-certificates X509 API compilation issues are resolved.
// Wire-up: add `extension KoalaRootCA: CAManaging {}` in SecurityServices.swift.

@MainActor
protocol CAManaging: AnyObject, Observable {
    var isGenerated: Bool { get }
    var isTrusted: Bool { get }
    /// Generates a new keypair and self-signed cert, persisting to Keychain.
    func generate() throws
    /// Removes CA keypair from Keychain and resets in-memory state.
    func deleteFromKeychain() throws
    func certificatePEM() throws -> String
}

// MARK: - TrustManaging protocol
//
// UI contract for trust install/uninstall. TrustInstaller conforms directly.

@MainActor
protocol TrustManaging: AnyObject, Observable {
    var status: TrustInstaller.Status { get }
    func refreshStatus() async
    func install(pemFileURL: URL) async throws
    func uninstall() async throws
}

// MARK: - KoalaRootCA + CAManaging conformance
extension KoalaRootCA: CAManaging {}

// MARK: - TrustInstaller + TrustManaging conformance
extension TrustInstaller: TrustManaging {}

// MARK: - CASettingsView

/// Sheet shown from ProxyControlView when user taps "Configure..." in the
/// HTTPS Interception row. Manages root CA lifecycle and trust install/uninstall.
struct CASettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Injected as concrete types; both conform to their protocols.
    // Swap to AnyObject+protocol via EnvironmentValues if needed.
    @Environment(KoalaRootCA.self) private var ca: KoalaRootCA
    @Environment(TrustInstaller.self) private var trustInstaller: TrustInstaller

    @State private var showRegenerateConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showUninstallConfirm = false
    @State private var operationError: String?
    @State private var operationSuccess: String?
    @State private var showAdvanced = false
    @State private var showExporter = false
    @State private var isWorking = false
    @State private var pemExportDocument: PEMDocument?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection
                    actionsSection
                    infoSection
                    advancedSection
                    feedbackBanners
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 540)
        .task { await trustInstaller.refreshStatus() }
        .confirmationDialog(
            "Regenerate CA?",
            isPresented: $showRegenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) { performRegenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing intercepted sessions may show certificate errors until clients reconnect.")
        }
        .confirmationDialog(
            "Delete CA?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the CA keypair from the Keychain. You will need to generate and install trust again.")
        }
        .confirmationDialog(
            "Uninstall trust?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) { performUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("HTTPS traffic will no longer be intercepted. You can reinstall at any time.")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: pemExportDocument,
            contentType: .data,
            defaultFilename: "KoalaRootCA.pem"
        ) { result in
            switch result {
            case .success: setSuccess("PEM exported.")
            case .failure(let err): setError(err.localizedDescription)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("HTTPS Interception")
                    .font(.headline)
                Text("Root CA management and trust installation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isWorking {
                ProgressView()
                    .scaleEffect(0.75)
                    .padding(.trailing, 4)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Status section

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                statusRow(
                    label: "CA:",
                    indicator: ca.isGenerated ? .green : .gray,
                    text: ca.isGenerated ? "Generated" : "Not generated"
                )
                statusRow(
                    label: "Trust:",
                    indicator: trustStatusColor,
                    text: trustStatusText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var trustStatusColor: Color {
        switch trustInstaller.status {
        case .installed: return .green
        case .notInstalled: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }

    private var trustStatusText: String {
        switch trustInstaller.status {
        case .installed: return "Installed in System Keychain"
        case .notInstalled: return "Not installed in System Keychain"
        case .error(let msg): return "Error: \(msg)"
        case .unknown: return "Checking..."
        }
    }

    private func statusRow(label: String, indicator: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Circle()
                .fill(indicator)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
        }
    }

    // MARK: Actions section

    private var actionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                caActions
                trustActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var caActions: some View {
        HStack(spacing: 8) {
            if !ca.isGenerated {
                actionButton("Generate CA", systemImage: "plus.circle") {
                    performGenerate()
                }
            }
            if ca.isGenerated {
                actionButton("Regenerate", systemImage: "arrow.clockwise", role: .destructive) {
                    showRegenerateConfirm = true
                }
                actionButton("Delete CA", systemImage: "trash", role: .destructive) {
                    showDeleteConfirm = true
                }
                actionButton("Export PEM", systemImage: "square.and.arrow.up") {
                    prepareExport()
                }
            }
        }
    }

    private var trustActions: some View {
        HStack(spacing: 8) {
            if ca.isGenerated && trustInstaller.status != .installed {
                actionButton("Install Trust", systemImage: "checkmark.shield") {
                    performInstallTrust()
                }
            }
            if trustInstaller.status == .installed {
                actionButton("Uninstall", systemImage: "xmark.shield", role: .destructive) {
                    showUninstallConfirm = true
                }
            }
        }
    }

    private func actionButton(
        _ label: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.medium))
        }
        .disabled(isWorking)
    }

    // MARK: Info section

    private var infoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                infoBullet("After installing trust, all HTTPS traffic through Koala forward proxy will be intercepted and captured.")
                infoBullet("Trust is required ONCE per Mac. Uninstall anytime via this panel or Keychain Access → System Roots → \"Koala Root CA\".")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("Info")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func infoBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(.caption).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Advanced section

    private var advancedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("Manual install command (if auto fails)")
                            .font(.caption.weight(.medium))
                    }
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    manualCommandBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("Advanced")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var manualCommandBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(manualInstallCommand)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(manualInstallCommand, forType: .string)
                setSuccess("Copied to clipboard.")
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    .font(.caption)
            }
        }
    }

    private var manualInstallCommand: String {
        "sudo security add-trusted-cert -d -r trustRoot \\\n" +
        "  -k /Library/Keychains/System.keychain \\\n" +
        "  ~/Library/Application\\ Support/Koala/CA.pem"
    }

    // MARK: Feedback banners

    @ViewBuilder
    private var feedbackBanners: some View {
        if let err = operationError {
            feedbackBanner(err, color: .red, icon: "exclamationmark.triangle.fill")
        }
        if let msg = operationSuccess {
            feedbackBanner(msg, color: .green, icon: "checkmark.circle.fill")
        }
    }

    private func feedbackBanner(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(color).lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Operations

    private func performGenerate() {
        clearFeedback()
        isWorking = true
        Task {
            do {
                try ca.generate() // also calls saveToKeychain() internally
                setSuccess("CA generated and saved to Keychain.")
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func performRegenerate() {
        clearFeedback()
        isWorking = true
        Task {
            do {
                try ca.generate()
                setSuccess("CA regenerated.")
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func performDelete() {
        clearFeedback()
        isWorking = true
        Task {
            do {
                try ca.deleteFromKeychain()
                setSuccess("CA deleted from Keychain.")
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func performInstallTrust() {
        clearFeedback()
        isWorking = true
        Task {
            do {
                let pem = try ca.certificatePEM()
                let dir = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first!.appendingPathComponent("Koala")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let pemURL = dir.appendingPathComponent("CA.pem")
                try pem.write(to: pemURL, atomically: true, encoding: .utf8)
                try await trustInstaller.install(pemFileURL: pemURL)
                setSuccess("Trust installed. HTTPS interception active.")
            } catch TrustInstaller.InstallError.cancelled {
                isWorking = false
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func performUninstall() {
        clearFeedback()
        isWorking = true
        Task {
            do {
                try await trustInstaller.uninstall()
                setSuccess("Trust uninstalled.")
            } catch TrustInstaller.InstallError.cancelled {
                isWorking = false
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func prepareExport() {
        clearFeedback()
        guard let pem = try? ca.certificatePEM() else {
            setError("Failed to export PEM.")
            return
        }
        pemExportDocument = PEMDocument(content: pem)
        showExporter = true
    }

    // MARK: Helpers

    private func setError(_ msg: String) {
        isWorking = false
        operationError = msg
        operationSuccess = nil
    }

    private func setSuccess(_ msg: String) {
        isWorking = false
        operationSuccess = msg
        operationError = nil
    }

    private func clearFeedback() {
        operationError = nil
        operationSuccess = nil
    }
}

// MARK: - PEMDocument

/// FileDocument wrapper for exporting PEM via fileExporter.
struct PEMDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .text] }

    let content: String

    init(content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let str = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadUnknownStringEncoding)
        }
        content = str
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(content.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
