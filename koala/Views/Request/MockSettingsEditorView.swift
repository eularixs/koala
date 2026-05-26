import SwiftUI

// MARK: - MockSettingsEditorView

struct MockSettingsEditorView: View {
    @Binding var request: KoalaRequest
    @Environment(AppState.self) private var appState
    @Environment(MockServerService.self) private var mockService

    @State private var selectedServerId: UUID? = nil
    @State private var endpoint: MockEndpoint = .empty
    @State private var isSyncing = false
    @State private var syncError: String? = nil
    @State private var syncedFlash: Bool = false
    @State private var showRules: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                enableToggle
                if request.isMock {
                    if appState.mockServers.isEmpty {
                        noServerBanner
                    } else {
                        serverPicker
                        mockURLField
                        responseEditor
                        rulesSection
                        syncBar
                    }
                }
            }
            .padding(16)
        }
        .onAppear { initState() }
        .onChange(of: request.isMock) { _, on in if on { initState() } }
        .onChange(of: selectedServerId) { _, _ in loadEndpoint() }
        .onChange(of: request.method) { _, _ in endpoint.method = HTTPMethod(rawValue: request.method.rawValue) ?? .get }
        .onChange(of: request.url) { _, _ in endpoint.path = derivedPath }
    }

    // MARK: - Sections

    private var enableToggle: some View {
        Toggle("Enable Mock for this request", isOn: $request.isMock)
            .toggleStyle(.switch)
    }

    private var noServerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("No mock server in this project. Create one from the Mock Servers section.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var serverPicker: some View {
        HStack {
            Text("Mock Server")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Picker("", selection: $selectedServerId) {
                ForEach(appState.mockServers) { s in
                    Text(s.name).tag(Optional(s.id))
                }
            }
            .labelsHidden()
        }
    }

    private var mockURLField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mock URL")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(derivedMockURL)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var responseEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default Response")
                .font(.headline)

            HStack(spacing: 16) {
                statusCodeField
                delayField
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Body (JSON)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                CodeEditorView(text: bodyBinding, language: "json", minHeight: 180)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Response Headers")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                KeyValueEditorView(items: $endpoint.responseHeaders, showHeader: false)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var statusCodeField: some View {
        HStack(spacing: 6) {
            Text("Status").font(.caption).foregroundStyle(.secondary)
            TextField("200", value: $endpoint.statusCode, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var delayField: some View {
        HStack(spacing: 6) {
            Text("Delay (ms)").font(.caption).foregroundStyle(.secondary)
            TextField("0", value: $endpoint.delayMs, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation { showRules.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showRules ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("Conditional Rules")
                            .font(.headline)
                        Text("(\(endpoint.rules.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if showRules {
                    Button {
                        endpoint.rules.append(MockResponseRule())
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if showRules {
                if endpoint.rules.isEmpty {
                    Text("No rules. Default Response above is returned for all requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                ForEach($endpoint.rules) { $rule in
                    RuleEditorCard(rule: $rule, onDelete: {
                        endpoint.rules.removeAll { $0.id == rule.id }
                    })
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Sync

    private var syncBar: some View {
        HStack {
            if let err = syncError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if syncedFlash {
                Label("Synced to Vercel KV", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button {
                Task { await sync() }
            } label: {
                if isSyncing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Syncing...")
                    }
                } else {
                    Label("Sync to Mock Server", systemImage: "icloud.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing || selectedServerId == nil)
        }
    }

    // MARK: - State Bindings

    private var bodyBinding: Binding<String> {
        Binding(
            get: { endpoint.staticResponse?.body ?? "" },
            set: { endpoint.staticResponse = StaticResponse(body: $0) }
        )
    }

    // MARK: - Helpers

    private func initState() {
        if selectedServerId == nil {
            selectedServerId = appState.mockServers.first?.id
        }
        loadEndpoint()
    }

    private func loadEndpoint() {
        guard let sid = selectedServerId,
              let server = appState.mockServers.first(where: { $0.id == sid }) else {
            endpoint = freshEndpoint()
            return
        }
        let method = HTTPMethod(rawValue: request.method.rawValue) ?? .get
        let path = derivedPath
        if let existing = server.endpoints.first(where: { $0.method == method && $0.path == path }) {
            endpoint = existing
        } else {
            endpoint = freshEndpoint()
        }
    }

    private func freshEndpoint() -> MockEndpoint {
        MockEndpoint(
            path: derivedPath,
            method: HTTPMethod(rawValue: request.method.rawValue) ?? .get,
            responseMode: .staticJSON,
            staticResponse: StaticResponse(body: "{\n  \"ok\": true\n}"),
            statusCode: 200,
            responseHeaders: [KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true)],
            delayMs: 0,
            isEnabled: true
        )
    }

    private func sync() async {
        guard let sid = selectedServerId,
              var server = appState.mockServers.first(where: { $0.id == sid }) else { return }
        isSyncing = true
        syncError = nil
        syncedFlash = false
        defer { isSyncing = false }

        // Upsert endpoint
        if let idx = server.endpoints.firstIndex(where: { $0.method == endpoint.method && $0.path == endpoint.path }) {
            server.endpoints[idx] = endpoint
        } else {
            server.endpoints.append(endpoint)
        }
        appState.updateMockServer(server)

        do {
            try await mockService.saveEndpoint(endpoint, to: server)
            syncedFlash = true
            try? await Task.sleep(for: .seconds(2))
            syncedFlash = false
        } catch {
            syncError = error.localizedDescription
        }
    }

    private var derivedPath: String {
        let resolved = VariableResolver.resolve(
            request.url,
            environment: appState.selectedEnvironment,
            globals: appState.globalVariables
        )
        guard let parsed = URL(string: resolved), !parsed.path.isEmpty else { return "/" }
        return parsed.path.hasPrefix("/") ? parsed.path : "/\(parsed.path)"
    }

    private var derivedMockURL: String {
        guard let sid = selectedServerId,
              let server = appState.mockServers.first(where: { $0.id == sid }),
              !server.deploymentURL.isEmpty else {
            return "(no mock server selected)"
        }
        let base = server.deploymentURL.hasPrefix("http") ? server.deploymentURL : "https://\(server.deploymentURL)"
        return "\(base)\(derivedPath)"
    }
}

// MARK: - RuleEditorCard

private struct RuleEditorCard: View {
    @Binding var rule: MockResponseRule
    let onDelete: () -> Void

    @State private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $rule.isEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                Text("\(rule.statusCode)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                Text("\(rule.conditions.count) cond")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                conditionsBlock
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Status").font(.caption).foregroundStyle(.secondary)
                        TextField("200", value: $rule.statusCode, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 6) {
                        Text("Delay (ms)").font(.caption).foregroundStyle(.secondary)
                        TextField("0", value: $rule.delayMs, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .font(.system(.body, design: .monospaced))
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body (JSON)").font(.caption).foregroundStyle(.secondary)
                    CodeEditorView(text: $rule.body, language: "json", minHeight: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Response Headers").font(.caption).foregroundStyle(.secondary)
                    KeyValueEditorView(items: $rule.responseHeaders, showHeader: false)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private var conditionsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Conditions (ALL must match)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    rule.conditions.append(MockCondition())
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach($rule.conditions) { $cond in
                ConditionRow(cond: $cond, onDelete: {
                    rule.conditions.removeAll { $0.id == cond.id }
                })
            }
        }
    }
}

private struct ConditionRow: View {
    @Binding var cond: MockCondition
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $cond.source) {
                ForEach(ConditionSource.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            TextField("key / json path", text: $cond.key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            Picker("", selection: $cond.op) {
                ForEach(ConditionOperator.allCases, id: \.self) { o in
                    Text(o.rawValue).tag(o)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            TextField("value", text: $cond.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .disabled(cond.op == .exists || cond.op == .notExists)

            Button(action: onDelete) {
                Image(systemName: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#Preview("MockSettingsEditorView") {
    @Previewable @State var request = KoalaRequest(
        url: "https://api.example.com/users/123",
        isMock: true
    )
    MockSettingsEditorView(request: $request)
        .environment(AppState())
        .environment(MockServerService(vercelService: VercelService()))
        .frame(width: 700, height: 700)
}
