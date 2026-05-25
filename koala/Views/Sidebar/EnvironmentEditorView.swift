import SwiftUI

struct EnvironmentEditorView: View {
    @Binding var environment: KoalaEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var localEnv: KoalaEnvironment

    init(environment: Binding<KoalaEnvironment>) {
        _environment = environment
        _localEnv = State(initialValue: environment.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            KeyValueEditorView(
                items: Binding<[KeyValuePair]>(
                    get: { localEnv.variables.asKeyValuePairs },
                    set: { localEnv.variables = $0.asEnvVariables(preserving: localEnv.variables) }
                ),
                showSecretToggle: true
            )
            .padding(12)
            Spacer()
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) { dismiss() }
            Spacer()
            TextField("Environment name", text: $localEnv.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Spacer()
            Button("Done") {
                environment = localEnv
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
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
    @Previewable @State var env = KoalaEnvironment(
        name: "Production",
        variables: [
            EnvVariable(key: "BASE_URL", value: "https://api.example.com", isEnabled: true),
            EnvVariable(key: "API_KEY", value: "secret123", isSecret: true, isEnabled: true)
        ]
    )
    EnvironmentEditorView(environment: $env)
}
