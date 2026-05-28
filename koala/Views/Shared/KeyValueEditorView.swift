import SwiftUI

struct KeyValueEditorView: View {
    @Binding var items: [KeyValuePair]

    var showDescription: Bool = false
    var showSecretToggle: Bool = false
    /// When true, render a lock button beside the eye button to toggle
    /// per-row `isVault`. Requires `vaultService` + `vaultProjectId` in the
    /// SwiftUI environment to actually persist secrets to the Keychain.
    var showVaultToggle: Bool = false
    var showHeader: Bool = true
    var keyPlaceholder: String = "Key"
    var valuePlaceholder: String = "Value"

    @Environment(\.vaultService) private var vaultService
    @Environment(\.vaultProjectId) private var vaultProjectId

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                headerRow
                Divider()
            }
            ForEach($items) { $item in
                KeyValueRowView(
                    item: $item,
                    showDescription: showDescription,
                    showSecretToggle: showSecretToggle,
                    showVaultToggle: showVaultToggle,
                    keyPlaceholder: keyPlaceholder,
                    valuePlaceholder: valuePlaceholder,
                    vaultService: vaultService,
                    vaultProjectId: vaultProjectId,
                    onKeyChange: { handleKeyChange(for: item) },
                    onDelete: { deleteItem(item) }
                )
                Divider().padding(.leading, 8)
            }
            addButton
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var trailingWidth: CGFloat {
        var w: CGFloat = 28 // delete
        if showSecretToggle { w += 24 }
        if showVaultToggle { w += 24 }
        return w
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 24)
            Spacer().frame(width: 8)
            Text(keyPlaceholder)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(valuePlaceholder)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showDescription {
                Text("Description")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(width: trailingWidth)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.secondary.opacity(0.05))
    }

    private var addButton: some View {
        Button {
            items.append(KeyValuePair(isEnabled: true))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.callout)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleKeyChange(for item: KeyValuePair) {
        guard let last = items.last, last.id == item.id, !item.key.isEmpty else { return }
        items.append(KeyValuePair(isEnabled: true))
    }

    private func deleteItem(_ item: KeyValuePair) {
        // If the row was vault-backed, also delete from Keychain so we don't
        // leak orphaned secrets.
        if item.isVault, !item.key.isEmpty,
           let vault = vaultService, let pid = vaultProjectId {
            vault.delete(item.key, projectId: pid)
        }
        items.removeAll { $0.id == item.id }
    }
}

// MARK: - Row

private struct KeyValueRowView: View {
    @Binding var item: KeyValuePair
    let showDescription: Bool
    let showSecretToggle: Bool
    let showVaultToggle: Bool
    let keyPlaceholder: String
    let valuePlaceholder: String
    let vaultService: VaultService?
    let vaultProjectId: UUID?
    let onKeyChange: () -> Void
    let onDelete: () -> Void

    /// In-memory plaintext for vault rows. Never bound directly to `item.value`
    /// because we don't want SwiftUI to round-trip it through the persisted model.
    @State private var vaultDraft: String = ""

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: $item.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 24)

            Spacer().frame(width: 8)

            TextField(keyPlaceholder, text: $item.key)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                .onChange(of: item.key) { _, _ in onKeyChange() }

            valueField
                .frame(maxWidth: .infinity)

            if showDescription {
                TextField("Description", text: $item.description)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }

            if showVaultToggle {
                vaultToggleButton
                    .frame(width: 24)
            }

            if showSecretToggle {
                secretToggleButton
                    .frame(width: 24)
            }

            deleteButton
                .frame(width: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(item.isEnabled ? 1.0 : 0.5)
        .onAppear { syncVaultDraftFromStore() }
        .onChange(of: item.isVault) { _, newValue in
            if newValue {
                syncVaultDraftFromStore()
            }
        }
    }

    @ViewBuilder
    private var valueField: some View {
        if item.isVault {
            SecureField("••• stored in vault", text: $vaultDraft)
                .textFieldStyle(.plain)
                .onChange(of: vaultDraft) { _, newValue in
                    writeVaultDraft(newValue)
                }
        } else if item.isSecret {
            SecureField(valuePlaceholder, text: $item.value)
                .textFieldStyle(.plain)
        } else {
            TextField(valuePlaceholder, text: $item.value)
                .textFieldStyle(.plain)
        }
    }

    private var secretToggleButton: some View {
        Button {
            item.isSecret.toggle()
        } label: {
            Image(systemName: item.isSecret ? "eye.slash" : "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(item.isSecret ? "Show value" : "Mask as secret")
    }

    private var vaultToggleButton: some View {
        Button {
            toggleVault()
        } label: {
            Image(systemName: item.isVault ? "lock.fill" : "lock")
                .font(.caption)
                .foregroundStyle(item.isVault ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(item.isVault
              ? "Stored in macOS Keychain. Not synced via Collaboration."
              : "Move to Vault (Keychain-only, not synced)")
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete row")
    }

    // MARK: - Vault helpers

    private func toggleVault() {
        if item.isVault {
            // Moving out of vault: remove Keychain entry. Plaintext stays
            // empty (user must re-enter if they want a plain value).
            if !item.key.isEmpty,
               let vault = vaultService, let pid = vaultProjectId {
                vault.delete(item.key, projectId: pid)
            }
            item.isVault = false
            item.value = ""
            vaultDraft = ""
        } else {
            // Moving into vault: take whatever plaintext was in `value` and
            // push it to the Keychain, then clear from model.
            item.isVault = true
            let existing = item.value
            item.value = ""
            vaultDraft = existing
            writeVaultDraft(existing)
        }
    }

    private func writeVaultDraft(_ newValue: String) {
        guard item.isVault, !item.key.isEmpty,
              let vault = vaultService, let pid = vaultProjectId else { return }
        try? vault.set(item.key, value: newValue, projectId: pid)
    }

    private func syncVaultDraftFromStore() {
        guard item.isVault, !item.key.isEmpty,
              let vault = vaultService, let pid = vaultProjectId else { return }
        vaultDraft = vault.get(item.key, projectId: pid) ?? ""
    }
}

// MARK: - Preview

#Preview("KeyValueEditorView") {
    @Previewable @State var items: [KeyValuePair] = [
        KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true),
        KeyValuePair(key: "Authorization", value: "Bearer token123", isEnabled: true, isSecret: true),
        KeyValuePair(key: "X-Api-Key", value: "", isEnabled: false),
    ]

    VStack(spacing: 20) {
        Text("Headers Editor").font(.headline)
        KeyValueEditorView(
            items: $items,
            showDescription: true,
            showSecretToggle: true,
            showVaultToggle: true
        )

        Text("Params Editor").font(.headline)
        KeyValueEditorView(items: $items)
    }
    .padding()
    .frame(width: 640)
}
