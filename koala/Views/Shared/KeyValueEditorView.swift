import SwiftUI

struct KeyValueEditorView: View {
    @Binding var items: [KeyValuePair]

    var showDescription: Bool = false
    var showSecretToggle: Bool = false
    var showHeader: Bool = true
    var keyPlaceholder: String = "Key"
    var valuePlaceholder: String = "Value"

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
                    keyPlaceholder: keyPlaceholder,
                    valuePlaceholder: valuePlaceholder,
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
            Spacer().frame(width: showSecretToggle ? 52 : 28)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleKeyChange(for item: KeyValuePair) {
        guard let last = items.last, last.id == item.id, !item.key.isEmpty else { return }
        items.append(KeyValuePair(isEnabled: true))
    }

    private func deleteItem(_ item: KeyValuePair) {
        items.removeAll { $0.id == item.id }
    }
}

// MARK: - Row

private struct KeyValueRowView: View {
    @Binding var item: KeyValuePair
    let showDescription: Bool
    let showSecretToggle: Bool
    let keyPlaceholder: String
    let valuePlaceholder: String
    let onKeyChange: () -> Void
    let onDelete: () -> Void

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

            if showSecretToggle {
                secretToggleButton
                    .frame(width: 28)
            }

            deleteButton
                .frame(width: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(item.isEnabled ? 1.0 : 0.5)
    }

    @ViewBuilder
    private var valueField: some View {
        if item.isSecret {
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

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete row")
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
            showSecretToggle: true
        )

        Text("Params Editor").font(.headline)
        KeyValueEditorView(items: $items)
    }
    .padding()
    .frame(width: 640)
}
