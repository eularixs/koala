import SwiftUI

// MARK: - NewEnvironmentSheet (small dialog — name + color only)

struct NewEnvironmentSheet: View {
    let onCreate: (KoalaEnvironment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var colorHex: String? = nil

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Environment").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Create") {
                    var env = KoalaEnvironment()
                    env.name = name.trimmingCharacters(in: .whitespaces)
                    env.color = colorHex
                    onCreate(env)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Name")
                            .frame(width: 80, alignment: .leading)
                        TextField("e.g. Production", text: $name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 14)
                    HStack(spacing: 12) {
                        Text("Color")
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(palette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if colorHex == hex {
                                            Circle().stroke(Color.primary, lineWidth: 2)
                                        }
                                    }
                                    .onTapGesture { colorHex = hex }
                            }
                            Button {
                                colorHex = nil
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - EnvironmentDetailView (right-panel, embedded — full editor)

/// Embedded in MainDetailRouter when sidebar section = .environments.
/// Edits the selected env directly in-place (auto-save via Binding).
struct EnvironmentDetailView: View {
    @Environment(AppState.self) private var appState
    let environmentId: UUID

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"
    ]

    private var envIndex: Int? {
        appState.environments.firstIndex(where: { $0.id == environmentId })
    }

    var body: some View {
        @Bindable var state = appState
        if let idx = envIndex {
            let envBinding = $state.environments[idx]
            VStack(spacing: 0) {
                header(env: envBinding.wrappedValue)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionTitle("General")
                        groupedCard {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Text("Name")
                                        .frame(width: 100, alignment: .leading)
                                    TextField("e.g. Production", text: envBinding.name)
                                        .textFieldStyle(.plain)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: envBinding.name.wrappedValue) { _, _ in
                                            appState.saveToDisk()
                                        }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                Divider().padding(.leading, 14)
                                HStack(spacing: 12) {
                                    Text("Color")
                                        .frame(width: 100, alignment: .leading)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        ForEach(palette, id: \.self) { hex in
                                            Circle()
                                                .fill(Color(hex: hex) ?? .gray)
                                                .frame(width: 20, height: 20)
                                                .overlay {
                                                    if envBinding.color.wrappedValue == hex {
                                                        Circle().stroke(Color.primary, lineWidth: 2)
                                                    }
                                                }
                                                .onTapGesture {
                                                    envBinding.color.wrappedValue = hex
                                                    appState.saveToDisk()
                                                }
                                        }
                                        Button {
                                            envBinding.color.wrappedValue = nil
                                            appState.saveToDisk()
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }

                        sectionTitle("Variables")
                        KeyValueEditorView(
                            items: Binding<[KeyValuePair]>(
                                get: { envBinding.variables.wrappedValue.asKeyValuePairs },
                                set: { newVal in
                                    envBinding.variables.wrappedValue = newVal.asEnvVariables(preserving: envBinding.variables.wrappedValue)
                                    appState.saveToDisk()
                                }
                            ),
                            showSecretToggle: true,
                            showVaultToggle: true
                        )
                    }
                    .padding(20)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "leaf")
                    .font(.system(size: 36))
                    .foregroundStyle(.quaternary)
                Text("Environment not found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline).foregroundStyle(.primary)
    }

    @ViewBuilder
    private func groupedCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
    }

    private func header(env: KoalaEnvironment) -> some View {
        HStack(spacing: 10) {
            if let hex = env.color, let c = Color(hex: hex) {
                Circle().fill(c).frame(width: 14, height: 14)
            } else {
                Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1).frame(width: 14, height: 14)
            }
            Text(env.name).font(.headline)
            Spacer()
            Button {
                appState.selectedEnvironmentId = env.id
            } label: {
                Label("Use as active", systemImage: "checkmark.circle")
                    .font(.callout)
            }
            .disabled(appState.selectedEnvironmentId == env.id)
        }
        .padding(12)
    }
}

// MARK: - EnvironmentPlaceholderView

struct EnvironmentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Select an environment")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick from the sidebar or create a new one.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                isSecret: ev.isSecret,
                isVault: ev.isVault
            )
        }
    }
}

extension Array where Element == KeyValuePair {
    func asEnvVariables(preserving existing: [EnvVariable]) -> [EnvVariable] {
        map { kv in
            if let match = existing.first(where: { $0.id == kv.id }) {
                return EnvVariable(id: match.id, key: kv.key, value: kv.value, isSecret: kv.isSecret, isEnabled: kv.isEnabled, isVault: kv.isVault)
            }
            return EnvVariable(id: kv.id, key: kv.key, value: kv.value, isSecret: kv.isSecret, isEnabled: kv.isEnabled, isVault: kv.isVault)
        }
    }
}

// MARK: - Legacy compat — keep old EnvironmentEditorView name but redirect to embedded for old callers

/// Deprecated: legacy sheet-based editor. Kept as compatibility shim — calls the
/// new NewEnvironmentSheet for create, or just dismisses for edit (use right
/// panel instead).
struct EnvironmentEditorView: View {
    let isNew: Bool
    let onSave: (KoalaEnvironment) -> Void
    @State private var env: KoalaEnvironment

    init(environment: KoalaEnvironment, isNew: Bool = false, onSave: @escaping (KoalaEnvironment) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _env = State(initialValue: environment)
    }

    var body: some View {
        if isNew {
            NewEnvironmentSheet(onCreate: onSave)
        } else {
            // Edit no longer supported via sheet — users should use right-panel editor.
            VStack(spacing: 12) {
                Text("Edit in the main panel")
                    .font(.headline)
                Text("Select this environment from the sidebar to edit it in the right panel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .frame(width: 360, height: 200)
        }
    }
}

// MARK: - Preview

#Preview {
    NewEnvironmentSheet(onCreate: { _ in })
}
