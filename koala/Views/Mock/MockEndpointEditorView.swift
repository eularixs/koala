import SwiftUI

// MARK: - MockEndpointEditorView

struct MockEndpointEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (MockEndpoint) -> Void
    @State private var endpoint: MockEndpoint

    @State private var staticBody: String
    @State private var jsScript: String

    init(endpoint: MockEndpoint, onSave: @escaping (MockEndpoint) -> Void) {
        self.onSave = onSave
        _endpoint = State(initialValue: endpoint)
        _staticBody = State(initialValue: endpoint.staticResponse?.body ?? "{}")
        _jsScript = State(initialValue: endpoint.dynamicScript ?? "// return a JSON-serialisable value\nreturn { message: 'hello' }")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                formContent
                    .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 580)
        .frame(minHeight: 620)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Edit Endpoint")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            pathMethodSection
            responseModeSection
            responseBodySection
            headersSection
            delaySection
            enabledSection
        }
    }

    private var pathMethodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Path & Method", systemImage: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Menu {
                    ForEach(HTTPMethod.allCases) { method in
                        Button(method.displayName) { endpoint.method = method }
                    }
                } label: {
                    Text(endpoint.method.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(endpoint.method.color)
                        .frame(width: 80)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(endpoint.method.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                TextField("/api/users/:id", text: $endpoint.path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var responseModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Response Mode", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Response Mode", selection: $endpoint.responseMode) {
                ForEach(ResponseMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var responseBodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Response Body", systemImage: "curlybraces")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if endpoint.responseMode == .staticJSON {
                    statusCodeStepper
                }
            }
            if endpoint.responseMode == .staticJSON {
                CodeEditorView(text: $staticBody, language: "json", minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    CodeEditorView(text: $jsScript, language: "javascript", minHeight: 160)
                    Label("Saving dynamic JS requires redeploy after first setup.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusCodeStepper: some View {
        HStack(spacing: 6) {
            Text("Status")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(value: $endpoint.statusCode, in: 100...599, step: 1) {
                Text("\(endpoint.statusCode)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .frame(width: 34)
            }
        }
    }

    private var headersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Response Headers", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            KeyValueEditorView(items: $endpoint.responseHeaders)
        }
    }

    private var delaySection: some View {
        HStack {
            Label("Delay (ms)", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: $endpoint.delayMs, in: 0...60000, step: 100) {
                Text("\(endpoint.delayMs) ms")
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }

    private var enabledSection: some View {
        Toggle("Endpoint Enabled", isOn: $endpoint.isEnabled)
            .toggleStyle(.switch)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.escape)
            Spacer()
            Button("Save") { commitAndDismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func commitAndDismiss() {
        if endpoint.responseMode == .staticJSON {
            endpoint.staticResponse = StaticResponse(body: staticBody)
            endpoint.dynamicScript = nil
        } else {
            endpoint.dynamicScript = jsScript
            endpoint.staticResponse = nil
        }
        onSave(endpoint)
        dismiss()
    }
}

#Preview {
    MockEndpointEditorView(endpoint: .empty) { _ in }
}
