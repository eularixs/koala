import Foundation
import Observation

/// Live state of a streaming connection (WebSocket or SSE).
enum StreamConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .error(let m): return "Error: \(m)"
        }
    }
}

/// WebSocket client wrapper around `URLSessionWebSocketTask` with an
/// auto-running receive loop that appends incoming frames to
/// `receivedMessages`.
@MainActor
@Observable
final class WebSocketService {
    var state: StreamConnectionState = .disconnected
    var receivedMessages: [StreamMessage] = []
    /// Round-trip ping latency in ms (most recent successful ping). `nil` until first ping.
    var latencyMs: Int? = nil

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    func connect(url: URL, headers: [String: String]) async throws {
        disconnect()
        state = .connecting

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        self.session = session

        var request = URLRequest(url: url)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        state = .connected
        startReceiveLoop()
        startPingLoop()
    }

    func send(_ text: String) async throws {
        guard let task else {
            throw StreamError.notConnected
        }
        try await task.send(.string(text))
        receivedMessages.append(
            StreamMessage(direction: .outgoing, text: text, isBinary: false)
        )
    }

    func sendBinary(_ data: Data) async throws {
        guard let task else {
            throw StreamError.notConnected
        }
        try await task.send(.data(data))
        receivedMessages.append(
            StreamMessage(
                direction: .outgoing,
                text: "<\(data.count) bytes>",
                isBinary: true
            )
        )
    }

    func disconnect() {
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if case .connected = state {
            state = .disconnected
        } else if case .connecting = state {
            state = .disconnected
        }
    }

    func clearMessages() {
        receivedMessages.removeAll()
    }

    // MARK: - Internals

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while let self, !Task.isCancelled, let task = self.currentTask() {
                do {
                    let message = try await task.receive()
                    self.handle(message)
                } catch {
                    self.handleReceiveError(error)
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self.sendPing()
            }
        }
    }

    private func currentTask() -> URLSessionWebSocketTask? { task }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            receivedMessages.append(
                StreamMessage(direction: .incoming, text: text, isBinary: false)
            )
        case .data(let data):
            let preview = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            receivedMessages.append(
                StreamMessage(direction: .incoming, text: preview, isBinary: true)
            )
        @unknown default:
            break
        }
    }

    private func handleReceiveError(_ error: Error) {
        if case .connected = state {
            state = .error(error.localizedDescription)
        }
    }

    private func sendPing() {
        guard let task else { return }
        let start = Date()
        task.sendPing { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error == nil {
                    self.latencyMs = Int(Date().timeIntervalSince(start) * 1000)
                }
            }
        }
    }
}

enum StreamError: LocalizedError {
    case notConnected
    case invalidURL
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:          return "Not connected"
        case .invalidURL:            return "Invalid URL"
        case .connectionFailed(let m): return m
        }
    }
}
