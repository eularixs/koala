import SwiftUI

// MARK: - VaultManagerSheet
//
// Simple manager for the active project's Keychain-backed vault variables.
// Lists every entry tracked by `VaultService.allNames(projectId:)`, lets the
// user reveal / edit / delete each value, and add new ones. Values are stored
// directly in the Keychain — they never touch the JSON persistence layer or
// collaboration bundle.

struct VaultManagerSheet: View {
    let projectId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.vaultService) private var vaultService

    @State private var rows: [Row] = []
    @State private var newName: String = ""

    private struct Row: Identifiable {
        let id = UUID()
        var name: String
        var value: String
        var revealed: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 540)
        .frame(minHeight: 200, maxHeight: 500)
        .onAppear { reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.accentColor)
            Text("Vault")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Secrets stored in the macOS Keychain. Never written to disk JSON or synced via Collaboration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.open")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("No vault entries yet")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach($rows) { $row in
                            rowView(for: $row)
                            Divider()
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                }

                addRow
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func rowView(for row: Binding<Row>) -> some View {
        HStack(spacing: 8) {
            Text(row.wrappedValue.name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

            Group {
                if row.wrappedValue.revealed {
                    TextField("Value", text: row.value)
                        .textFieldStyle(.plain)
                } else {
                    SecureField("Value", text: row.value)
                        .textFieldStyle(.plain)
                }
            }
            .onChange(of: row.wrappedValue.value) { _, newValue in
                try? vaultService?.set(row.wrappedValue.name, value: newValue, projectId: projectId)
            }

            Button {
                row.wrappedValue.revealed.toggle()
            } label: {
                Image(systemName: row.wrappedValue.revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(row.wrappedValue.revealed ? "Hide value" : "Reveal value")

            Button(role: .destructive) {
                delete(name: row.wrappedValue.name)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete vault entry")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("New vault variable name", text: $newName)
                .textFieldStyle(.roundedBorder)
            Button {
                addNew()
            } label: {
                Label("Add vault var", systemImage: "plus")
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Actions

    private func reload() {
        guard let vault = vaultService else { rows = []; return }
        rows = vault.allNames(projectId: projectId).map { name in
            Row(name: name, value: vault.get(name, projectId: projectId) ?? "", revealed: false)
        }
    }

    private func addNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let vault = vaultService else { return }
        // Don't allow blank duplicates; updating an existing name just edits it.
        if !rows.contains(where: { $0.name == trimmed }) {
            try? vault.set(trimmed, value: "", projectId: projectId)
            rows.append(Row(name: trimmed, value: "", revealed: true))
        }
        newName = ""
    }

    private func delete(name: String) {
        vaultService?.delete(name, projectId: projectId)
        rows.removeAll { $0.name == name }
    }
}

#Preview {
    VaultManagerSheet(projectId: UUID())
        .environment(\.vaultService, VaultService())
}
