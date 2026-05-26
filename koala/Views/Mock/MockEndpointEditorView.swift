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
            rulesSection
            responseModeSection
            responseBodySection
            headersSection
            delaySection
            enabledSection
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Rules", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(endpoint.rules.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    endpoint.rules.append(MockResponseRule(name: "Rule \(endpoint.rules.count + 1)"))
                } label: {
                    Label("Add Rule", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if endpoint.rules.isEmpty {
                Text("No rules. Default response below will be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach($endpoint.rules) { $rule in
                        MockRuleRowView(rule: $rule) {
                            endpoint.rules.removeAll { $0.id == rule.id }
                        }
                    }
                }
            }
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

// MARK: - MockRuleRowView

private struct MockRuleRowView: View {
    @Binding var rule: MockResponseRule
    var onDelete: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if isExpanded {
                Divider()
                expandedContent
                    .padding(10)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            Toggle("", isOn: $rule.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            TextField("Rule name", text: $rule.name)
                .textFieldStyle(.plain)
                .font(.callout.weight(.semibold))

            Text("\(rule.statusCode)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

            Text("\(rule.conditions.count) cond")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete rule")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            conditionsBlock
            statusAndDelayRow
            headersBlock
            bodyBlock
        }
    }

    private var conditionsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Conditions (all must match)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    rule.conditions.append(MockCondition())
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            if rule.conditions.isEmpty {
                Text("No conditions — rule always matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach($rule.conditions) { $cond in
                        conditionRow(cond: $cond)
                    }
                }
            }
        }
    }

    private func conditionRow(cond: Binding<MockCondition>) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(ConditionSource.allCases) { src in
                    Button(src.displayName) { cond.wrappedValue.source = src }
                }
            } label: {
                Text(cond.wrappedValue.source.displayName)
                    .font(.caption)
                    .frame(width: 80, alignment: .leading)
            }
            .menuStyle(.borderlessButton)

            TextField("key", text: cond.key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity)

            Menu {
                ForEach(ConditionOperator.allCases) { op in
                    Button(op.displayName) { cond.wrappedValue.op = op }
                }
            } label: {
                Text(cond.wrappedValue.op.displayName)
                    .font(.caption)
                    .frame(width: 84, alignment: .leading)
            }
            .menuStyle(.borderlessButton)

            let needsValue = cond.wrappedValue.op != .exists && cond.wrappedValue.op != .notExists
            TextField("value", text: cond.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity)
                .disabled(!needsValue)
                .opacity(needsValue ? 1.0 : 0.4)

            Button {
                let id = cond.wrappedValue.id
                rule.conditions.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusAndDelayRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $rule.statusCode, in: 100...599, step: 1) {
                    Text("\(rule.statusCode)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .frame(width: 34)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Text("Delay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $rule.delayMs, in: 0...60000, step: 100) {
                    Text("\(rule.delayMs) ms")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private var headersBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Response Headers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            KeyValueEditorView(items: $rule.responseHeaders)
        }
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Response Body")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            CodeEditorView(text: $rule.body, language: "json", minHeight: 120)
        }
    }
}

#Preview {
    MockEndpointEditorView(endpoint: .empty) { _ in }
}
