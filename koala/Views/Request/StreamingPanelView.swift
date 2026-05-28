import SwiftUI

// MARK: - Streaming Service Protocol

/// Common surface shared by `WebSocketService` and `SSEService` so the
/// streaming panel can drive either without branching everywhere.
@MainActor
protocol StreamingService: AnyObject {
    var state: StreamConnectionState { get }
    var receivedMessages: [StreamMessage] { get }
    var latencyMs: Int? { get }

    func connect(url: URL, headers: [String: String]) async throws
    func disconnect()
    func clearMessages()
}

extension WebSocketService: StreamingService {}
extension SSEService: StreamingService {}

// MARK: - Streaming Mode

enum StreamingMode {
    case webSocket
    case sse

    var canSend: Bool {
        switch self {
        case .webSocket: return true
        case .sse:       return false
        }
    }

    var connectVerb: String {
        switch self {
        case .webSocket: return "Connect"
        case .sse:       return "Subscribe"
        }
    }
}

// MARK: - StreamingPanelView

struct StreamingPanelView: View {
    @Binding var request: KoalaRequest
    let mode: StreamingMode

    // The underlying observable service. We accept both flavors here
    // and pick whichever matches `mode` at runtime.
    var webSocket: WebSocketService?
    var sse: SSEService?

    @State private var composerText: String = ""
    @State private var sendError: String? = nil

    init(
        request: Binding<KoalaRequest>,
        mode: StreamingMode,
        webSocket: WebSocketService? = nil,
        sse: SSEService? = nil
    ) {
        self._request = request
        self.mode = mode
        self.webSocket = webSocket
        self.sse = sse
    }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                connectionHeader
                Divider()
                messagesList
            }
            .frame(minHeight: 200, idealHeight: 360)

            if mode.canSend {
                composer
                    .frame(minHeight: 110, idealHeight: 140)
            }
        }
    }

    // MARK: - Header

    private var connectionHeader: some View {
        HStack(spacing: 10) {
            statusDot
            Text(currentState.label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let ms = currentLatency {
                Text("\(ms) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            Spacer()

            Button {
                clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear messages")
            .disabled(messages.isEmpty)

            connectButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.35), lineWidth: 3)
                    .scaleEffect(isConnected ? 1.6 : 1.0)
                    .opacity(isConnected ? 0.0 : 0.0)
            )
    }

    private var statusColor: Color {
        switch currentState {
        case .disconnected: return .gray
        case .connecting:   return .yellow
        case .connected:    return .green
        case .error:        return .red
        }
    }

    private var connectButton: some View {
        Button(action: toggleConnection) {
            Text(buttonLabel)
                .frame(minWidth: 80)
        }
        .buttonStyle(.borderedProminent)
        .tint(isConnected ? .red : .accentColor)
        .disabled(request.url.trimmingCharacters(in: .whitespaces).isEmpty)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var buttonLabel: String {
        switch currentState {
        case .connected, .connecting: return "Disconnect"
        case .disconnected, .error:   return mode.connectVerb
        }
    }

    // MARK: - Messages

    private var messagesList: some View {
        Group {
            if messages.isEmpty {
                ContentUnavailableView(
                    "No messages",
                    systemImage: mode == .webSocket ? "bubble.left.and.bubble.right" : "dot.radiowaves.left.and.right",
                    description: Text(isConnected
                        ? "Waiting for events…"
                        : "Press \(mode.connectVerb) to start.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(messages) { msg in
                                MessageRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Send Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let err = sendError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Button("Send") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConnected || composerText.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }

            TextEditor(text: $composerText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .padding(12)
    }

    // MARK: - Service accessors

    private var currentState: StreamConnectionState {
        webSocket?.state ?? sse?.state ?? .disconnected
    }

    private var currentLatency: Int? {
        webSocket?.latencyMs ?? sse?.latencyMs
    }

    private var messages: [StreamMessage] {
        webSocket?.receivedMessages ?? sse?.receivedMessages ?? []
    }

    private var isConnected: Bool {
        if case .connected = currentState { return true }
        return false
    }

    // MARK: - Actions

    private func toggleConnection() {
        switch currentState {
        case .connected, .connecting:
            webSocket?.disconnect()
            sse?.disconnect()
        case .disconnected, .error:
            Task { await connect() }
        }
    }

    private func connect() async {
        let raw = request.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw) else {
            sendError = "Invalid URL"
            return
        }
        let headers = Dictionary(uniqueKeysWithValues:
            request.headers
                .filter { $0.isEnabled && !$0.key.isEmpty }
                .map { ($0.key, $0.value) }
        )
        do {
            if let ws = webSocket {
                try await ws.connect(url: url, headers: headers)
            } else if let s = sse {
                try await s.connect(url: url, headers: headers)
            }
            sendError = nil
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func sendMessage() {
        guard let ws = webSocket else { return }
        let payload = composerText
        Task {
            do {
                try await ws.send(payload)
                composerText = ""
                sendError = nil
            } catch {
                sendError = error.localizedDescription
            }
        }
    }

    private func clear() {
        webSocket?.clearMessages()
        sse?.clearMessages()
    }
}

// MARK: - MessageRow

private struct MessageRow: View {
    let message: StreamMessage
    @State private var isExpanded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: directionIcon)
                    .font(.caption2)
                    .foregroundStyle(directionColor)
                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let name = message.eventName, !name.isEmpty {
                    Text(name)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(directionColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(directionColor)
                }
                if message.isBinary {
                    Text("BIN")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            Text(message.text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : 3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(directionColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(directionColor.opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if message.text.count > 200 {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }
        }
    }

    private var directionIcon: String {
        switch message.direction {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        }
    }

    private var directionColor: Color {
        switch message.direction {
        case .incoming: return .blue
        case .outgoing: return .green
        }
    }
}
