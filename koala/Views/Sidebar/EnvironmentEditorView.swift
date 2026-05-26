import SwiftUI

// MARK: - EnvironmentEditorView

/// TablePlus-style sectioned editor for a KoalaEnvironment. Caller controls
/// persistence via `onSave` (called only on Save button) — Cancel simply dismisses
/// so a "create" flow can discard the draft.
struct EnvironmentEditorView: View {
    let isNew: Bool
    let onSave: (KoalaEnvironment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localEnv: KoalaEnvironment

    init(environment: KoalaEnvironment, isNew: Bool = false, onSave: @escaping (KoalaEnvironment) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _localEnv = State(initialValue: environment)
    }

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .frame(minWidth: 540, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isNew ? "New Environment" : "Edit Environment")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("Save") {
                onSave(localEnv)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(localEnv.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("General")
                groupedCard {
                    formRow("Name") {
                        TextField("e.g. Production", text: $localEnv.name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                }

                sectionTitle("Color")
                groupedCard {
                    formRow("Color") {
                        HStack(spacing: 6) {
                            ForEach(palette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        if localEnv.color == hex {
                                            Circle().stroke(Color.primary, lineWidth: 2)
                                        }
                                    }
                                    .onTapGesture { localEnv.color = hex }
                            }
                            Button {
                                localEnv.color = nil
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                    }
                }

                sectionTitle("Variables")
                KeyValueEditorView(
                    items: Binding<[KeyValuePair]>(
                        get: { localEnv.variables.asKeyValuePairs },
                        set: { localEnv.variables = $0.asEnvVariables(preserving: localEnv.variables) }
                    ),
                    showSecretToggle: true
                )
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline)
    }

    @ViewBuilder
    private func groupedCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 80, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - EnvVariable <-> KeyValuePair conversion

extension Array where Element == EnvVariable {
    var asKeyValuePairs: [KeyValuePair] {
        map { ev in
            KeyValuePair(
                id: ev.id,
                key: ev.key,
                value: ev.value,
                description: "",
                isEnabled: ev.isEnabled,
                isSecret: ev.isSecret
            )
        }
    }
}

extension Array where Element == KeyValuePair {
    func asEnvVariables(preserving existing: [EnvVariable]) -> [EnvVariable] {
        map { kv in
            if let match = existing.first(where: { $0.id == kv.id }) {
                return EnvVariable(id: match.id, key: kv.key, value: kv.value, isSecret: kv.isSecret, isEnabled: kv.isEnabled)
            }
            return EnvVariable(id: kv.id, key: kv.key, value: kv.value, isSecret: kv.isSecret, isEnabled: kv.isEnabled)
        }
    }
}

// MARK: - Preview

#Preview {
    EnvironmentEditorView(
        environment: KoalaEnvironment(
            name: "Production",
            variables: [
                EnvVariable(key: "BASE_URL", value: "https://api.example.com", isEnabled: true)
            ]
        ),
        isNew: false,
        onSave: { _ in }
    )
}
