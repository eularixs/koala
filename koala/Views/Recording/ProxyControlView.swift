import SwiftUI

// MARK: - ProxyControlView
//
// Config panel that sits at the top of RecordingDashboardView.
// Shows mode picker, upstream rules editor (reverse only),
// local port, status badge, Start/Stop, and capture filter.
struct ProxyControlView: View {
    @Bindable var proxy: RecordingProxyService
    @Binding var port: Int
    var onStartError: (String) -> Void = { _ in }

    // Sheet state for adding a new upstream rule
    @State private var showAddRule = false
    @State private var newPrefix: String = ""
    @State private var newUpstreamText: String = ""
    @State private var newRuleError: String? = nil

    // Sheet state for adding a path glob filter
    @State private var showAddGlob = false
    @State private var newGlob: String = ""

    // Sheet state for adding a domain allowlist entry
    @State private var showAddDomain = false
    @State private var newDomain: String = ""

    // Rule pending delete confirmation
    @State private var ruleToDelete: UpstreamRule? = nil

    // HTTPS Interception sheet
    @State private var showCASheet = false

    // System proxy auto-config
    @State private var systemProxyBusy = false
    @State private var systemProxyError: String? = nil
    @State private var showManualCommandSheet = false
    @State private var manualCommand: String = ""
    @State private var manualCommandTitle: String = ""

    private var isRunning: Bool {
        if case .listening = proxy.state { return true }
        return false
    }

    private var isReverse: Bool {
        if case .reverse = proxy.mode { return true }
        return false
    }

    private var currentRules: [UpstreamRule] {
        if case .reverse(let rules) = proxy.mode { return rules }
        return []
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                modeRow
                if isReverse {
                    upstreamRulesSection
                }
                captureFilterSection
                browserLauncherRow
                systemProxyRow
                httpsInterceptionRow
                portAndControlRow
                helperText
            }
            .padding(.top, 6)
        } label: {
            Text("Proxy Config")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.bottom, 4)
        }
        .task { await SecurityServices.systemProxy.refreshState() }
        .onAppear {
            port = Int(proxy.port)
        }
        .sheet(isPresented: $showAddRule) { addRuleSheet }
        .sheet(isPresented: $showAddGlob) { addGlobSheet }
        .sheet(isPresented: $showAddDomain) { addDomainSheet }
        .sheet(isPresented: $showCASheet) {
            CASettingsView()
                .environment(SecurityServices.koalaRootCA)
                .environment(SecurityServices.trustInstaller)
        }
        .confirmationDialog(
            "Remove rule \"\(ruleToDelete?.pathPrefix ?? "")\"?",
            isPresented: Binding(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let rule = ruleToDelete { removeRule(rule) }
                ruleToDelete = nil
            }
            Button("Cancel", role: .cancel) { ruleToDelete = nil }
        }
    }

    // MARK: Mode row

    private var modeRow: some View {
        HStack(spacing: 12) {
            Text("Mode:")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 6) {
                modeButton("Reverse", selected: isReverse) {
                    guard !isRunning else { return }
                    if !isReverse {
                        proxy.mode = .reverse(rules: [])
                    }
                }
                modeButton("Forward", selected: !isReverse) {
                    guard !isRunning else { return }
                    proxy.mode = .forward
                }
            }
        }
    }

    private func modeButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(selected ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    // MARK: Upstream Rules section

    private var upstreamRulesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack {
                    Text("Prefix")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text("Upstream URL")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 2)

                ForEach(currentRules) { rule in
                    upstreamRuleRow(rule)
                }

                Button {
                    newPrefix = ""
                    newUpstreamText = ""
                    newRuleError = nil
                    showAddRule = true
                } label: {
                    Label("Add rule", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.accentColor)
                .disabled(isRunning)
                .padding(.top, 2)
            }
        } label: {
            Text("Upstream Rules")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)
        }
    }

    private func upstreamRuleRow(_ rule: UpstreamRule) -> some View {
        HStack(spacing: 6) {
            Text(rule.pathPrefix)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
            Text(rule.upstream.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                ruleToDelete = rule
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
    }

    private func removeRule(_ rule: UpstreamRule) {
        guard case .reverse(var rules) = proxy.mode else { return }
        rules.removeAll { $0.id == rule.id }
        proxy.mode = .reverse(rules: rules)
    }

    private func addRule() {
        let trimPrefix = newPrefix.trimmingCharacters(in: .whitespaces)
        let trimURL = newUpstreamText.trimmingCharacters(in: .whitespaces)

        guard !trimPrefix.isEmpty else { newRuleError = "Prefix is required."; return }
        guard trimPrefix.hasPrefix("/") else { newRuleError = "Prefix must start with /."; return }
        guard let url = URL(string: trimURL),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil else {
            newRuleError = "Must be a valid http(s) URL with a host."
            return
        }

        guard case .reverse(var rules) = proxy.mode else { return }
        let newRule = UpstreamRule(pathPrefix: trimPrefix, upstream: url)
        rules.append(newRule)
        // Keep "/" last (catch-all should be checked last in UI display too)
        rules.sort { a, b in
            if a.pathPrefix == "/" { return false }
            if b.pathPrefix == "/" { return true }
            return a.pathPrefix < b.pathPrefix
        }
        proxy.mode = .reverse(rules: rules)
        showAddRule = false
    }

    private var addRuleSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Upstream Rule")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Path Prefix").font(.caption).foregroundStyle(.secondary)
                TextField("/__auth", text: $newPrefix)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Upstream URL").font(.caption).foregroundStyle(.secondary)
                TextField("https://api.example.com", text: $newUpstreamText)
                    .textFieldStyle(.roundedBorder)
            }

            if let err = newRuleError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { showAddRule = false }
                Spacer()
                Button("Add") { addRule() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }

    // MARK: Capture filter section

    private var captureFilterSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $proxy.captureFilter.skipStaticAssets) {
                    Text("Skip static assets (HTML/CSS/JS/images)")
                        .font(.body)
                }
                .toggleStyle(.checkbox)
                .disabled(isRunning)

                filterChipRow(
                    label: "Domains",
                    placeholder: "All hosts captured",
                    items: proxy.captureFilter.domainAllowlist,
                    onAdd: { newDomain = ""; showAddDomain = true },
                    onRemove: { d in proxy.captureFilter.domainAllowlist.removeAll { $0 == d } }
                )

                filterChipRow(
                    label: "Paths",
                    placeholder: "All paths captured",
                    items: proxy.captureFilter.pathGlobs,
                    onAdd: { newGlob = ""; showAddGlob = true },
                    onRemove: { g in proxy.captureFilter.pathGlobs.removeAll { $0 == g } }
                )
            }
            .padding(.vertical, 2)
        } label: {
            Text("Capture Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)
        }
    }

    private func filterChipRow(
        label: String,
        placeholder: String,
        items: [String],
        onAdd: @escaping () -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            if items.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        filterChip(item) { onRemove(item) }
                    }
                    Spacer(minLength: 0)
                }
            }

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.18), in: Circle())
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
    }

    private func filterChip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.callout.monospaced())
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.18), in: Capsule())
    }

    private func domainRow(_ domain: String) -> some View {
        EmptyView()
    }

    private func globRow(_ glob: String) -> some View {
        HStack(spacing: 4) {
            Text(glob)
                .font(.caption.monospaced())
                .lineLimit(1)
            Spacer()
            Button {
                proxy.captureFilter.pathGlobs.removeAll { $0 == glob }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
    }

    private var addGlobSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Path Filter").font(.headline)
            Text("Use * for single segment, ** for any path.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("/api/**", text: $newGlob)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            HStack {
                Button("Cancel") { showAddGlob = false }
                Spacer()
                Button("Add") {
                    let trimmed = newGlob.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        proxy.captureFilter.pathGlobs.append(trimmed)
                    }
                    showAddGlob = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    private var addDomainSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Domain to Allowlist").font(.headline)
            Text("Substring match. e.g. 'eularix.com' matches api.eularix.com, auth.eularix.com, etc.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("eularix.com", text: $newDomain)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            HStack {
                Button("Cancel") { showAddDomain = false }
                Spacer()
                Button("Add") {
                    let trimmed = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
                    if !trimmed.isEmpty && !proxy.captureFilter.domainAllowlist.contains(trimmed) {
                        proxy.captureFilter.domainAllowlist.append(trimmed)
                    }
                    showAddDomain = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    // MARK: HTTPS Interception row

    private var httpsInterceptionRow: some View {
        GroupBox {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HTTPS Interception")
                        .font(.subheadline.weight(.semibold))
                    Text(caStatusDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Configure...") { showCASheet = true }
            }
        }
    }

    private var caStatusDescription: String {
        let ca = SecurityServices.koalaRootCA
        let trust = SecurityServices.trustInstaller
        switch (ca.isGenerated, trust.status) {
        case (false, _):       return "Not configured"
        case (true, .installed): return "Active — intercepting HTTPS"
        case (true, .notInstalled): return "CA generated, not trusted"
        case (true, .error):   return "Trust outdated"
        case (true, .unknown): return "CA generated, trust unknown"
        }
    }

    // MARK: System Proxy (forward mode helper)

    // MARK: Browser Launcher (no admin required)

    @ViewBuilder
    private var browserLauncherRow: some View {
        GroupBox {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browser Launcher")
                        .font(.subheadline.weight(.semibold))
                    Text(isRunning
                         ? "Launch a fresh browser window already wired to Koala. No admin password needed."
                         : "Start the proxy first.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Chrome (isolated profile)") { launchChrome() }
                    Button("Brave (isolated profile)") { launchBrave() }
                    Button("Firefox (isolated profile)") { launchFirefox() }
                    Divider()
                    Button("Copy curl prefix") { copyCurlPrefix() }
                    Button("Copy env vars (HTTP_PROXY/HTTPS_PROXY)") { copyEnvVars() }
                } label: {
                    Label("Launch...", systemImage: "safari")
                }
                .menuStyle(.borderedButton)
                .menuIndicator(.visible)
                .fixedSize()
                .disabled(!isRunning)
            }
        }
    }

    private func launchChrome() {
        let chromePath = "/Applications/Google Chrome.app"
        guard FileManager.default.fileExists(atPath: chromePath) else {
            systemProxyError = "Google Chrome not installed at /Applications"
            return
        }
        let profile = "/tmp/koala-chrome-\(Int(Date().timeIntervalSince1970))"
        let args = [
            "-na", "Google Chrome", "--args",
            "--proxy-server=http://localhost:\(port)",
            "--user-data-dir=\(profile)",
            "--disable-quic",
            "--disable-features=EncryptedClientHello,UseDnsHttpsSvcb",
            "--no-default-browser-check",
            "--incognito",
        ]
        runOpen(args)
    }

    private func launchBrave() {
        let app = "/Applications/Brave Browser.app"
        guard FileManager.default.fileExists(atPath: app) else {
            systemProxyError = "Brave not installed at /Applications"
            return
        }
        let profile = "/tmp/koala-brave-\(Int(Date().timeIntervalSince1970))"
        runOpen([
            "-na", "Brave Browser", "--args",
            "--proxy-server=http://localhost:\(port)",
            "--user-data-dir=\(profile)",
            "--disable-quic",
            "--no-default-browser-check",
            "--incognito",
        ])
    }

    private func launchFirefox() {
        let app = "/Applications/Firefox.app"
        guard FileManager.default.fileExists(atPath: app) else {
            systemProxyError = "Firefox not installed at /Applications"
            return
        }
        // Firefox doesn't accept proxy via CLI flag — needs prefs.js or profile config.
        // For now: launch it + remind user to set proxy in about:preferences.
        runOpen(["-na", "Firefox"])
        let alert = NSAlert()
        alert.messageText = "Firefox proxy setup"
        alert.informativeText = "Firefox doesn't support proxy via launch flag.\n\nIn Firefox: Settings → Network Settings → Manual proxy → HTTP: 127.0.0.1 : \(port), check 'Also use this proxy for HTTPS'."
        alert.runModal()
    }

    private func runOpen(_ arguments: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = arguments
        do { try proc.run() }
        catch { systemProxyError = error.localizedDescription }
    }

    private func copyCurlPrefix() {
        let cmd = "curl --proxy http://localhost:\(port) "
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    private func copyEnvVars() {
        let cmd = "export HTTP_PROXY=http://localhost:\(port) HTTPS_PROXY=http://localhost:\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    // MARK: System Proxy (advanced — needs admin; flaky in sandbox)

    @ViewBuilder
    private var systemProxyRow: some View {
        let sp = SecurityServices.systemProxy
        GroupBox {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("System Proxy")
                            .font(.subheadline.weight(.semibold))
                        if case .on = sp.state, !isRunning {
                            Text("ORPHANED")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange, in: Capsule())
                        }
                    }
                    Text(systemProxyDescription)
                        .font(.caption2)
                        .foregroundStyle(systemProxyError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                }
                Spacer()
                if systemProxyBusy {
                    ProgressView().controlSize(.small)
                } else {
                    switch sp.state {
                    case .on:
                        Button {
                            Task { await toggleSystemProxy(enable: false) }
                        } label: {
                            Label("Restore Default", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    default:
                        Button("Enable") { Task { await toggleSystemProxy(enable: true) } }
                            .disabled(!isRunning || isReverse)
                    }
                    Menu {
                        Button("Copy Enable command") {
                            Task { await copyShellCommand(enable: true) }
                        }
                        Button("Copy Disable command") {
                            Task { await copyShellCommand(enable: false) }
                        }
                        Button("Refresh State") {
                            Task { await SecurityServices.systemProxy.refreshState() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More options (Terminal fallback, refresh)")
                }
            }
        }
        .sheet(isPresented: $showManualCommandSheet) {
            manualCommandSheet
        }
    }

    private var manualCommandSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(manualCommandTitle)
                .font(.headline)
            Text("Sandbox AppleScript admin auth can fail on newer macOS. Paste this command into Terminal — admin password works reliably there.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(manualCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxHeight: 180)
            HStack {
                Button("Copy Again") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(manualCommand, forType: .string)
                }
                Spacer()
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                Button("Done") { showManualCommandSheet = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func copyShellCommand(enable: Bool) async {
        let sp = SecurityServices.systemProxy
        let cmd = enable
            ? await sp.enableCommand(port: UInt16(clamping: port))
            : await sp.disableCommand()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        manualCommand = cmd
        manualCommandTitle = enable ? "Enable System Proxy (Terminal)" : "Disable System Proxy (Terminal)"

        // Write a .command file and open it → Terminal auto-executes + sudo prompt
        // works natively (no AppleScript / sandbox auth issues).
        let scriptURL = URL(fileURLWithPath: "/tmp/koala-proxy-\(enable ? "enable" : "disable").command")
        let scriptBody = """
        #!/bin/bash
        set -e
        echo "Koala will now \(enable ? "enable" : "disable") the macOS system proxy on port \(port)."
        echo "Enter your Mac login password below when prompted."
        echo ""
        \(cmd)
        echo ""
        echo "Done. You can close this Terminal window."
        """
        do {
            try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
        } catch {
            systemProxyError = "Failed to launch Terminal: \(error.localizedDescription)"
            showManualCommandSheet = true   // fallback to manual copy/paste UI
            return
        }
        // Schedule refresh after a few seconds so UI reflects new state.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await SecurityServices.systemProxy.refreshState()
        }
    }

    private var systemProxyDescription: String {
        if let err = systemProxyError { return err }
        switch SecurityServices.systemProxy.state {
        case .unknown:    return "Checking..."
        case .off:
            if isReverse { return "Only used in Forward mode." }
            return isRunning ? "Click Enable to route all macOS traffic via Koala :\(port)." : "Start the proxy first, then click Enable."
        case .on(let h, let p):
            if isRunning {
                return "● Active — \(h):\(p) (click Restore when done to return network to normal)"
            } else {
                return "⚠ macOS is routing via \(h):\(p) but the proxy isn't listening. Click Restore Default now."
            }
        case .error(let m): return m
        }
    }

    private func toggleSystemProxy(enable: Bool) async {
        systemProxyBusy = true
        systemProxyError = nil
        defer { systemProxyBusy = false }
        do {
            if enable {
                try await SecurityServices.systemProxy.enable(port: UInt16(clamping: port))
            } else {
                try await SecurityServices.systemProxy.disable()
            }
        } catch ProxyConfigError.cancelled {
            // user dismissed admin sheet — silent
        } catch {
            systemProxyError = error.localizedDescription
        }
    }

    // MARK: Port + Start/Stop row

    private var portAndControlRow: some View {
        HStack(spacing: 12) {
            statusBadge

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                Text("Port")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", value: $port, format: .number.grouping(.never))
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
                    .onChange(of: port) { _, new in
                        proxy.port = UInt16(clamping: new)
                    }
                Stepper("", value: $port, in: 1024...65535)
                    .labelsHidden()
                    .disabled(isRunning)
            }

            Spacer()

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
                        onStartError(error.localizedDescription)
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isReverse && currentRules.isEmpty)
            }
        }
    }

    // MARK: Helper text

    @ViewBuilder
    private var helperText: some View {
        if isReverse {
            if currentRules.isEmpty {
                Text("Add at least one upstream rule to start.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Open http://localhost:\(port) in your browser. Captures group automatically by URL path.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("Configure system HTTP proxy to localhost:\(port). Captures all browser HTTP traffic.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Status badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(proxy.state.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.5))
        )
    }

    private var badgeColor: Color {
        switch proxy.state {
        case .listening: return .green
        case .error:     return .red
        case .stopped:   return .gray
        }
    }
}
