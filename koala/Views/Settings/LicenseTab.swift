import SwiftUI
import AppKit

// MARK: - LicenseTab

/// Settings tab for entering / inspecting a Koala license key.
/// Wired via `SettingsView` once `LicenseService` is injected into the env.
struct LicenseTab: View {
    @Environment(LicenseService.self) private var licenseService

    @State private var keyField: String = ""
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let buyURL = "https://koala.app/buy"

    var body: some View {
        Form {
            tierSection

            if licenseService.activeReceipt == nil {
                activationSection
            } else {
                activeLicenseSection
            }

            if let err = errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let info = infoMessage {
                Section {
                    Label(info, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tier badge

    private var tierSection: some View {
        Section {
            HStack(spacing: 12) {
                tierBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(tierTitle)
                        .font(.headline)
                    Text(tierSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var tierBadge: some View {
        Text(licenseService.tier.rawValue.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tierColor, in: Capsule())
    }

    private var tierColor: Color {
        switch licenseService.tier {
        case .free: return .gray
        case .pro: return .accentColor
        case .lifetime: return .purple
        }
    }

    private var tierTitle: String {
        switch licenseService.tier {
        case .free: return "Koala Free"
        case .pro: return "Koala Pro"
        case .lifetime: return "Koala Lifetime"
        }
    }

    private var tierSubtitle: String {
        switch licenseService.tier {
        case .free: return "Unlock collaboration, mock servers, and more with Koala Pro."
        case .pro: return "Thanks for supporting Koala. All Pro features unlocked."
        case .lifetime: return "Lifetime license. All current and future Pro features unlocked."
        }
    }

    // MARK: - Inactive (free) view

    private var activationSection: some View {
        Group {
            Section("Buy a License") {
                HStack {
                    Text("Don't have a license yet?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Buy Koala Pro") {
                        if let u = URL(string: buyURL) { NSWorkspace.shared.open(u) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Activate") {
                TextField("License Key", text: $keyField, prompt: Text("KOALA-XXXX-XXXX-XXXX"))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .disabled(licenseService.isLoading)

                HStack {
                    Spacer()
                    if licenseService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                    Button("Activate") { activate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty || licenseService.isLoading)
                }
            }
        }
    }

    // MARK: - Active (pro/lifetime) view

    private var activeLicenseSection: some View {
        Group {
            if let receipt = licenseService.activeReceipt {
                Section("License Details") {
                    LabeledContent("License ID") {
                        Text(receipt.licenseId)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    if let email = receipt.userEmail {
                        LabeledContent("Email") {
                            Text(email)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    LabeledContent("Activated") {
                        Text(receipt.activatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                    LabeledContent("Valid Until") {
                        Text(receipt.validUntil.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Button("Deactivate", role: .destructive) { deactivate() }
                            .disabled(licenseService.isLoading)
                        Spacer()
                        if licenseService.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 8)
                        }
                        Button("Re-validate Now") { revalidate() }
                            .disabled(licenseService.isLoading)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func activate() {
        errorMessage = nil
        infoMessage = nil
        let key = keyField
        Task {
            do {
                try await licenseService.activate(key: key)
                infoMessage = "License activated."
                keyField = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deactivate() {
        errorMessage = nil
        infoMessage = nil
        Task {
            do {
                try await licenseService.deactivate()
                infoMessage = "License deactivated."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revalidate() {
        errorMessage = nil
        infoMessage = nil
        Task {
            await licenseService.revalidateIfNeeded()
            if let err = licenseService.lastError {
                errorMessage = err
            } else {
                infoMessage = "License re-validated."
            }
        }
    }
}
