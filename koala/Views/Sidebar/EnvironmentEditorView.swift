import SwiftUI

struct EnvironmentEditorView: View {
    @Binding var environment: KoalaEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var localEnv: KoalaEnvironment

    init(environment: Binding<KoalaEnvironment>) {
        _environment = environment
        _localEnv = State(initialValue: environment.wrappedValue)
    }

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            colorRow
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
        .frame(minWidth: 520, minHeight: 440)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) { dismiss() }
            Spacer()
            HStack(spacing: 6) {
                if let hex = localEnv.color, let col = Color(hex: hex) {
                    Circle().fill(col).frame(width: 10, height: 10)
                }
                TextField("Environment name", text: $localEnv.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
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

    private var colorRow: some View {
        HStack(spacing: 6) {
            Text("Color")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 50, alignment: .leading)
            ForEach(palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 16, height: 16)
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
            .help("Clear color")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
