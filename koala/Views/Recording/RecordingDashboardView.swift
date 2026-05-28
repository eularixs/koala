import SwiftUI

// MARK: - RecordingDashboardView
//
// Layout:
//   [ Proxy / Start to begin capturing ]  [status] [mode tabs] [port] [Start] [⚙]
//   [ Search ............... ] [filter chip] [Save as Project] [Clear All]
//   ─────────────────────────────────────────────────────────────────────────
//   ▾ domain.com
//      [GET] /path                 200  142 ms  10:25:14
//      [POST] /api/login           201  88 ms   10:25:18
//   ▾ api.x.com
//      ...
//   ─────────────────────────────────────────────────────────────────────────
//   Selected request detail panel (request, response, timing, copy curl)

struct RecordingDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var proxy = RecordingProxyService()
    @State private var port: Int = 8080
    @State private var startError: String?
    @State private var selectedCaptureId: UUID?
    @State private var collapsedHosts: Set<String> = []
    @State private var convertSheetTarget: RecordedRequest?
    @State private var showSaveSheet = false
    @State private var showProxyConfig = false
    @State private var showHelp = false
    @State private var searchQuery: String = ""
    @State private var onlyErrorsFilter: Bool = false
    @State private var detailExpanded: Bool = false
    @State private var detailHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            actionsRow
            Divider()
            captureTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            detailDrawer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Proxy Error", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK") { startError = nil }
        } message: {
            Text(startError ?? "")
        }
        .sheet(isPresented: $showProxyConfig) {
            ProxyConfigSheet(proxy: proxy, port: $port) { msg in startError = msg }
        }
        .sheet(item: $convertSheetTarget) { capture in
            ConvertToMockSheet(capture: capture, mockServers: appState.mockServers) { server in
                Task { await convert(capture: capture, to: server) }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveAsProjectSheet(
                proxy: proxy,
                appState: appState,
                onSaved: { selectedCaptureId = nil }
            )
        }
        .sheet(isPresented: $showHelp) {
            ProxyHelpSheet(port: port)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording Proxy").font(.headline)
                Text(isRunning
                     ? "Capturing on port \(Int(proxy.port))"
                     : "Start to begin capturing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
            modeTabs
            portField
            startStopButton
            settingsButton
        }
        .padding(12)
    }

    private var isRunning: Bool {
        if case .listening = proxy.state { return true }
        return false
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(badgeColor)
                .frame(width: 7, height: 7)
            Text(badgeText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private var badgeColor: Color {
        switch proxy.state {
        case .stopped:   return .secondary
        case .listening: return .green
        case .error:     return .red
        }
    }

    private var badgeText: String {
        switch proxy.state {
        case .stopped:           return "Stopped"
        case .listening(let p):  return "Listening :\(p)"
        case .error(let m):      return m.prefix(28) + (m.count > 28 ? "…" : "")
        }
    }

    private var modeTabs: some View {
        let isReverse: Bool = {
            if case .reverse = proxy.mode { return true }
            return false
        }()
        return HStack(spacing: 2) {
            modeTab("Reverse", selected: isReverse) {
                guard !isRunning else { return }
                if !isReverse { proxy.mode = .reverse(rules: []) }
            }
            modeTab("Forward", selected: !isReverse) {
                guard !isRunning else { return }
                proxy.mode = .forward
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private func modeTab(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    private var portField: some View {
        HStack(spacing: 4) {
            Text("Port")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("8888", value: $port, formatter: NumberFormatter())
                .textFieldStyle(.plain)
                .frame(width: 52)
                .multilineTextAlignment(.center)
                .font(.callout.monospacedDigit())
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                .disabled(isRunning)
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        if isRunning {
            Button(role: .destructive) {
                proxy.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            Button {
                do {
                    try proxy.start(port: UInt16(clamping: port))
                } catch {
                    startError = error.localizedDescription
                }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled({
                if case .reverse(let rules) = proxy.mode, rules.isEmpty { return true }
                return false
            }())
        }
    }

    private var settingsButton: some View {
        Button {
            showProxyConfig = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body)
        }
        .help("Proxy settings")
    }

    // MARK: Actions row

    private var actionsRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search captures", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 340)

            Toggle(isOn: $onlyErrorsFilter) {
                Label("Errors only", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)

            Spacer()

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Proxy setup guide")

            Button {
                showSaveSheet = true
            } label: {
                Label("Save as Project", systemImage: "tray.and.arrow.down")
            }
            .disabled(proxy.captures.isEmpty)

            Button(role: .destructive) {
                proxy.clear()
                selectedCaptureId = nil
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(proxy.captures.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Capture table

    private var filteredCaptures: [RecordedRequest] {
        var items = proxy.captures
        if onlyErrorsFilter { items = items.filter { $0.responseStatus >= 400 } }
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.host.lowercased().contains(q) ||
                $0.path.lowercased().contains(q) ||
                $0.method.lowercased().contains(q)
            }
        }
        return items
    }

    private var groupedCaptures: [(host: String, items: [RecordedRequest])] {
        let groups = Dictionary(grouping: filteredCaptures, by: { $0.host })
        return groups
            .map { (host: $0.key, items: $0.value.sorted { $0.capturedAt > $1.capturedAt }) }
            .sorted { $0.host < $1.host }
    }

    @ViewBuilder
    private var captureTable: some View {
        if proxy.captures.isEmpty {
            emptyState
        } else if filteredCaptures.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.quaternary)
                Text("No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(groupedCaptures, id: \.host) { group in
                        domainSection(group: group)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func domainSection(group: (host: String, items: [RecordedRequest])) -> some View {
        let collapsed = collapsedHosts.contains(group.host)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(host: group.host)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(group.host)
                        .font(.callout.weight(.semibold))
                    Text("(\(group.items.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color.secondary.opacity(0.06))

            if !collapsed {
                ForEach(group.items) { item in
                    captureRow(item)
                        .background(selectedCaptureId == item.id ? Color.accentColor.opacity(0.18) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCaptureId = item.id
                            withAnimation(.easeInOut(duration: 0.18)) { detailExpanded = true }
                        }
                        .contextMenu {
                            Button("Copy as cURL") { copyCurl(item) }
                            Button("Convert to Mock Endpoint…") { convertSheetTarget = item }
                            Divider()
                            Button(role: .destructive) {
                                proxy.delete(item.id)
                                if selectedCaptureId == item.id { selectedCaptureId = nil }
                            } label: { Text("Delete") }
                        }
                    Divider().padding(.leading, 32).opacity(0.3)
                }
            }
        }
    }

    private func captureRow(_ item: RecordedRequest) -> some View {
        HStack(spacing: 10) {
            methodBadge(item.method)
                .frame(width: 56, alignment: .leading)
            Text(item.path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text("\(item.responseStatus)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(statusColor(item.responseStatus))
                .frame(width: 36, alignment: .trailing)
            Text("\(item.durationMs) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(timeFmt(item.capturedAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    private func methodBadge(_ method: String) -> some View {
        Text(method.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(methodColor(method), in: RoundedRectangle(cornerRadius: 3))
    }

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET":     return .blue
        case "POST":    return .green
        case "PUT":     return .orange
        case "DELETE":  return .red
        case "PATCH":   return .purple
        default:        return .gray
        }
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500...:    return .red
        default:        return .secondary
        }
    }

    private func timeFmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func toggle(host: String) {
        if collapsedHosts.contains(host) { collapsedHosts.remove(host) }
        else { collapsedHosts.insert(host) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No captures yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(isRunning
                 ? "Visit a site through the proxy to see traffic here."
                 : "Click Start, then route browser traffic through the proxy.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Detail drawer (collapsible from bottom — Postman-style)

    @ViewBuilder
    private var detailDrawer: some View {
        if let id = selectedCaptureId,
           let capture = proxy.captures.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                Divider()
                drawerHandle(capture: capture)
                if detailExpanded {
                    Divider()
                    CaptureDetailView(capture: capture, onCopyCurl: { copyCurl(capture) })
                        .frame(height: detailHeight)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        // when nothing selected: drawer hidden entirely (no "select a request" placeholder)
    }

    private func drawerHandle(capture: RecordedRequest) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    detailExpanded.toggle()
                }
            } label: {
                Image(systemName: detailExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)

            methodChipMini(capture.method)
            Text(capture.path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("\(capture.responseStatus)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(statusColor(capture.responseStatus))
            Text("\(capture.durationMs) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                selectedCaptureId = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close inspector")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.18)) { detailExpanded.toggle() }
        }
        .overlay(alignment: .top) {
            // drag-resize bar
            if detailExpanded {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 4)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let h = detailHeight - value.translation.height
                                detailHeight = min(max(140, h), 700)
                            }
                    )
                    .onHover { hovering in
                        if hovering { NSCursor.resizeUpDown.push() }
                        else { NSCursor.pop() }
                    }
            }
        }
    }

    private func methodChipMini(_ method: String) -> some View {
        Text(method.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(methodColor(method), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Helpers

    private func copyCurl(_ item: RecordedRequest) {
        var lines: [String] = ["curl -X \(item.method.uppercased()) '\(item.url)'"]
        for (k, v) in item.headers {
            let escaped = v.replacingOccurrences(of: "'", with: "'\\''")
            lines.append("  -H '\(k): \(escaped)'")
        }
        if let body = item.requestBodyString, !body.isEmpty {
            let escaped = body.replacingOccurrences(of: "'", with: "'\\''")
            lines.append("  --data '\(escaped)'")
        }
        let cmd = lines.joined(separator: " \\\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    private func convert(capture: RecordedRequest, to server: MockServer) async {
        let method = HTTPMethod(rawValue: capture.method.uppercased()) ?? .get
        let path: String = {
            if let comps = URLComponents(string: capture.url) {
                return comps.path.isEmpty ? "/" : comps.path
            }
            return "/"
        }()
        let bodyString = capture.responseBodyString ?? ""
        let respHeaders = capture.responseHeaders.map { (k, v) in
            KeyValuePair(key: k, value: v, isEnabled: true)
        }
        let endpoint = MockEndpoint(
            path: path,
            method: method,
            responseMode: .staticJSON,
            staticResponse: StaticResponse(body: bodyString),
            statusCode: capture.responseStatus,
            responseHeaders: respHeaders
        )
        var updated = server
        updated.endpoints.append(endpoint)
        appState.updateMockServer(updated)
        convertSheetTarget = nil
    }
}

// MARK: - ProxyConfigSheet (native Settings-style Form)

private struct ProxyConfigSheet: View {
    @Bindable var proxy: RecordingProxyService
    @Binding var port: Int
    var onStartError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAddRule = false
    @State private var newPrefix: String = ""
    @State private var newUpstreamText: String = ""
    @State private var newRuleError: String? = nil
    @State private var showAddDomain = false
    @State private var newDomain: String = ""
    @State private var showAddGlob = false
    @State private var newGlob: String = ""
    @State private var showCASheet = false
    @State private var systemProxyBusy = false
    @State private var systemProxyError: String? = nil

    private var isReverse: Bool {
        if case .reverse = proxy.mode { return true }
        return false
    }

    private var currentRules: [UpstreamRule] {
        if case .reverse(let rules) = proxy.mode { return rules }
        return []
    }

    private var isRunning: Bool {
        if case .listening = proxy.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                modeSection
                if isReverse { upstreamRulesSection }
                captureFilterSection
                browserLauncherSection
                systemProxySection
                httpsInterceptionSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 680)
        .sheet(isPresented: $showAddRule) { addRuleSheet }
        .sheet(isPresented: $showAddDomain) { addDomainSheet }
        .sheet(isPresented: $showAddGlob) { addGlobSheet }
        .sheet(isPresented: $showCASheet) { CASettingsView().environment(SecurityServices.koalaRootCA).environment(SecurityServices.trustInstaller) }
        .task { await SecurityServices.systemProxy.refreshState() }
    }

    private var header: some View {
        HStack {
            Text("Proxy Settings").font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Mode

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { isReverse ? "reverse" : "forward" },
                set: { newVal in
                    guard !isRunning else { return }
                    if newVal == "reverse", !isReverse { proxy.mode = .reverse(rules: []) }
                    if newVal == "forward", isReverse { proxy.mode = .forward }
                }
            )) {
                Text("Reverse").tag("reverse")
                Text("Forward").tag("forward")
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)

            LabeledContent("Port") {
                TextField("", value: $port, formatter: NumberFormatter())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
            }
        }
    }

    // MARK: Upstream Rules

    private var upstreamRulesSection: some View {
        Section {
            if currentRules.isEmpty {
                Text("No rules yet. Add at least one to start the proxy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(currentRules) { rule in
                    HStack(spacing: 12) {
                        Text(rule.pathPrefix)
                            .font(.callout.monospaced())
                            .frame(width: 100, alignment: .leading)
                        Text(rule.upstream.absoluteString)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            removeRule(rule)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning)
                    }
                }
            }
            Button {
                newPrefix = ""; newUpstreamText = ""; newRuleError = nil
                showAddRule = true
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .disabled(isRunning)
        } header: {
            Text("Upstream Rules")
        } footer: {
            Text("Routes browser path prefixes to upstream URLs. Longest prefix wins.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Capture Filter

    private var captureFilterSection: some View {
        Section {
            Toggle("Skip static assets (HTML/CSS/JS/images)", isOn: $proxy.captureFilter.skipStaticAssets)
                .disabled(isRunning)

            chipRow(label: "Domains",
                    placeholder: "All hosts",
                    items: proxy.captureFilter.domainAllowlist,
                    onAdd: { newDomain = ""; showAddDomain = true },
                    onRemove: { d in proxy.captureFilter.domainAllowlist.removeAll { $0 == d } })

            chipRow(label: "Paths",
                    placeholder: "All paths",
                    items: proxy.captureFilter.pathGlobs,
                    onAdd: { newGlob = ""; showAddGlob = true },
                    onRemove: { g in proxy.captureFilter.pathGlobs.removeAll { $0 == g } })
        } header: {
            Text("Capture Filter")
        }
    }

    private func chipRow(
        label: String,
        placeholder: String,
        items: [String],
        onAdd: @escaping () -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                if items.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 4) {
                            Text(item)
                                .font(.caption.monospaced())
                            Button {
                                onRemove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunning)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                    }
                }
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
        }
    }

    // MARK: Browser Launcher

    private var browserLauncherSection: some View {
        Section {
            LabeledContent("Launch with proxy") {
                Menu {
                    Button("Chrome (isolated)") { launchChrome() }
                    Button("Brave (isolated)") { launchBrave() }
                    Divider()
                    Button("Copy curl prefix") { copyCurlPrefix() }
                    Button("Copy env vars") { copyEnvVars() }
                } label: {
                    Label("Launch…", systemImage: "safari")
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                .disabled(!isRunning)
            }
        } header: {
            Text("Browser Launcher")
        } footer: {
            Text("Opens a fresh browser already wired to Koala. No admin needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: System Proxy

    private var systemProxySection: some View {
        Section {
            LabeledContent {
                if systemProxyBusy {
                    ProgressView().controlSize(.small)
                } else {
                    switch SecurityServices.systemProxy.state {
                    case .on:
                        Button {
                            Task { await toggleSystemProxy(enable: false) }
                        } label: {
                            Label("Restore Default", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    default:
                        Button("Enable System Proxy") {
                            Task { await toggleSystemProxy(enable: true) }
                        }
                        .disabled(!isRunning || isReverse)
                    }
                }
            } label: {
                statusInline
            }
        } header: {
            Text("System Proxy")
        } footer: {
            if let err = systemProxyError {
                Text(err).font(.caption).foregroundStyle(.red)
            } else {
                Text(systemProxyFooter).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusInline: some View {
        let sp = SecurityServices.systemProxy
        return HStack(spacing: 6) {
            switch sp.state {
            case .on(let h, let p):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Active — \(h):\(p)")
            case .off:
                Image(systemName: "circle").foregroundStyle(.secondary)
                Text("Off")
            case .unknown:
                ProgressView().controlSize(.mini)
                Text("Checking…").foregroundStyle(.secondary)
            case .error(let m):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(m).lineLimit(1)
            }
        }
    }

    private var systemProxyFooter: String {
        switch SecurityServices.systemProxy.state {
        case .on(let h, let p):
            return isRunning
                ? "macOS is routing all HTTP/HTTPS via \(h):\(p)."
                : "⚠️ macOS routes via \(h):\(p) but proxy isn't listening. Restore Default to fix."
        case .off:
            return isReverse
                ? "Only used in Forward mode."
                : "Routes all macOS HTTP/HTTPS via Koala. Admin password needed once."
        default: return ""
        }
    }

    // MARK: HTTPS Interception

    private var httpsInterceptionSection: some View {
        Section {
            LabeledContent("Status") {
                Button("Configure…") { showCASheet = true }
            }
        } header: {
            Text("HTTPS Interception")
        } footer: {
            Text(caStatusDescription).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var caStatusDescription: String {
        let ca = SecurityServices.koalaRootCA
        let trust = SecurityServices.trustInstaller
        switch (ca.isGenerated, trust.status) {
        case (false, _):            return "CA not generated. Click Configure to set up."
        case (true, .installed):    return "Active — intercepting HTTPS traffic."
        case (true, .notInstalled): return "CA generated, trust not installed."
        case (true, .error):        return "Trust setup error — open Configure."
        case (true, .unknown):      return "CA generated, trust status unknown."
        }
    }

    // MARK: Add sheets

    private var addRuleSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Upstream Rule").font(.headline)
            LabeledContent("Prefix") {
                TextField("/__auth", text: $newPrefix)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Upstream URL") {
                TextField("https://api.example.com", text: $newUpstreamText)
                    .textFieldStyle(.roundedBorder)
            }
            if let err = newRuleError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddRule = false }
                Button("Add") { addRule() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var addDomainSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Domain Filter").font(.headline)
            Text("Substring match. 'eularix.com' captures api.eularix.com, auth.eularix.com, etc.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("eularix.com", text: $newDomain)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showAddDomain = false }
                Button("Add") {
                    let t = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
                    if !t.isEmpty && !proxy.captureFilter.domainAllowlist.contains(t) {
                        proxy.captureFilter.domainAllowlist.append(t)
                    }
                    showAddDomain = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var addGlobSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Path Filter").font(.headline)
            Text("Use * for single segment, ** for any path.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("/api/**", text: $newGlob)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showAddGlob = false }
                Button("Add") {
                    let t = newGlob.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { proxy.captureFilter.pathGlobs.append(t) }
                    showAddGlob = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: Actions

    private func removeRule(_ rule: UpstreamRule) {
        guard case .reverse(var rules) = proxy.mode else { return }
        rules.removeAll { $0.id == rule.id }
        proxy.mode = .reverse(rules: rules)
    }

    private func addRule() {
        let p = newPrefix.trimmingCharacters(in: .whitespaces)
        let u = newUpstreamText.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { newRuleError = "Prefix is required."; return }
        guard p.hasPrefix("/") else { newRuleError = "Prefix must start with /."; return }
        guard let url = URL(string: u), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil else {
            newRuleError = "Must be a valid http(s) URL."
            return
        }
        guard case .reverse(var rules) = proxy.mode else { return }
        rules.append(UpstreamRule(pathPrefix: p, upstream: url))
        proxy.mode = .reverse(rules: rules)
        showAddRule = false
    }

    private func toggleSystemProxy(enable: Bool) async {
        systemProxyBusy = true; systemProxyError = nil
        defer { systemProxyBusy = false }
        do {
            if enable {
                try await SecurityServices.systemProxy.enable(port: UInt16(clamping: port))
            } else {
                try await SecurityServices.systemProxy.disable()
            }
        } catch ProxyConfigError.cancelled {
            // silent
        } catch {
            systemProxyError = error.localizedDescription
        }
    }

    private func launchChrome() {
        let app = "/Applications/Google Chrome.app"
        guard FileManager.default.fileExists(atPath: app) else { return }
        runOpen(["-na", "Google Chrome", "--args",
                 "--proxy-server=http://localhost:\(port)",
                 "--user-data-dir=/tmp/koala-chrome-\(Int(Date().timeIntervalSince1970))",
                 "--disable-quic",
                 "--no-default-browser-check", "--incognito"])
    }

    private func launchBrave() {
        let app = "/Applications/Brave Browser.app"
        guard FileManager.default.fileExists(atPath: app) else { return }
        runOpen(["-na", "Brave Browser", "--args",
                 "--proxy-server=http://localhost:\(port)",
                 "--user-data-dir=/tmp/koala-brave-\(Int(Date().timeIntervalSince1970))",
                 "--disable-quic", "--no-default-browser-check", "--incognito"])
    }

    private func runOpen(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = args
        try? p.run()
    }

    private func copyCurlPrefix() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("curl --proxy http://localhost:\(port) ", forType: .string)
    }

    private func copyEnvVars() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("export HTTP_PROXY=http://localhost:\(port) HTTPS_PROXY=http://localhost:\(port)", forType: .string)
    }
}

// MARK: - ProxyHelpSheet

private struct ProxyHelpSheet: View {
    let port: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Proxy Setup Guide")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("Reverse mode") {
                        Text("Add upstream rules → Start → open http://localhost:\(port) in browser. Best for single-domain backends. Multi-subdomain SPAs may bypass via absolute URLs; use Forward + MITM for those.")
                    }
                    section("Forward + HTTPS MITM (full coverage)") {
                        VStack(alignment: .leading, spacing: 4) {
                            step(1, "Settings → HTTPS Interception → Generate CA + Install Trust (once per Mac)")
                            step(2, "Settings → Mode = Forward, then Start")
                            step(3, "Settings → System Proxy → Enable (or Browser Launcher → Chrome)")
                            step(4, "Visit real URL in browser (incognito) — login normally")
                        }
                    }
                    section("Per-app override") {
                        Text("HTTP_PROXY=http://localhost:\(port) HTTPS_PROXY=http://localhost:\(port) <command>")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 480)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(n).")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - CaptureDetailView (bottom panel)

private struct CaptureDetailView: View {
    let capture: RecordedRequest
    var onCopyCurl: () -> Void

    @State private var tab: DetailTab = .response

    enum DetailTab: String, CaseIterable, Identifiable {
        case request = "Request"
        case response = "Response"
        case headers = "Headers"
        case timing = "Timing"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .request:  requestPanel
                    case .response: responsePanel
                    case .headers:  headersPanel
                    case .timing:   timingPanel
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            methodChip(capture.method)
            Text(capture.path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(capture.responseStatus)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(statusColor(capture.responseStatus))
            Text("\(capture.durationMs) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                onCopyCurl()
            } label: {
                Label("cURL", systemImage: "doc.on.doc")
            }
            .help("Copy as cURL command")
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(capture.method) \(capture.url)")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let body = capture.requestBodyString, !body.isEmpty {
                Text("Body").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                codeBlock(body)
            } else {
                Text("No request body").font(.caption).foregroundStyle(.tertiary).italic()
            }
        }
    }

    private var responsePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let body = capture.responseBodyString, !body.isEmpty {
                codeBlock(body)
            } else {
                Text("Empty body").font(.caption).foregroundStyle(.tertiary).italic()
            }
        }
    }

    private var headersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            headerList(capture.headers)
            Divider()
            Text("Response").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            headerList(capture.responseHeaders)
        }
    }

    private var timingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Captured at", value: capture.capturedAt.formatted(date: .abbreviated, time: .standard))
            row("Duration", value: "\(capture.durationMs) ms")
            row("Status", value: "\(capture.responseStatus)")
            row("Host", value: capture.host)
            row("Method", value: capture.method.uppercased())
            row("URL", value: capture.url)
        }
    }

    private func row(_ k: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(k).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func headerList(_ h: [String: String]) -> some View {
        if h.isEmpty {
            Text("none").font(.caption).foregroundStyle(.tertiary).italic()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(h.keys.sorted(), id: \.self) { k in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(k):").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        Text(h[k] ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func methodChip(_ method: String) -> some View {
        Text(method.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(methodColor(method), in: RoundedRectangle(cornerRadius: 3))
    }

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET":     return .blue
        case "POST":    return .green
        case "PUT":     return .orange
        case "DELETE":  return .red
        case "PATCH":   return .purple
        default:        return .gray
        }
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500...:    return .red
        default:        return .secondary
        }
    }
}

// MARK: - SaveAsProjectSheet

private struct SaveAsProjectSheet: View {
    let proxy: RecordingProxyService
    let appState: AppState
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var projectName: String = ""
    @FocusState private var nameFocused: Bool

    private var placeholder: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return "Recorded \(fmt.string(from: Date()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as Project")
                .font(.headline)
            Text("Groups \(proxy.captures.count) capture(s) into collections by URL path.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $projectName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    proxy.saveAsProject(name: projectName, into: appState)
                    onSaved()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { nameFocused = true }
    }
}

// MARK: - ConvertToMockSheet

private struct ConvertToMockSheet: View {
    let capture: RecordedRequest
    let mockServers: [MockServer]
    let onConfirm: (MockServer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Convert to Mock Endpoint")
                .font(.headline)
            Text("Add this capture as a static-response endpoint to one of your mock servers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if mockServers.isEmpty {
                Text("No mock servers in this project. Create one first.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 12)
            } else {
                Picker("Mock Server", selection: $selectedId) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(mockServers) { server in
                        Text(server.name).tag(server.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()
            Text("\(capture.method) \(capture.path)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    if let sid = selectedId,
                       let server = mockServers.first(where: { $0.id == sid }) {
                        onConfirm(server)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedId == nil || mockServers.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
