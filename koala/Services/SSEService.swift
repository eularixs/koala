import Foundation
import Observation

/// Server-Sent Events client using `URLSession.bytes(for:)` line-streaming.
///
/// Parses the SSE wire format:
/// ```
/// event: <name>
/// data:  <payload>
/// data:  <more payload>
///                       <-- blank line dispatches the event
/// ```
@MainActor
@Observable
final class SSEService {
    var state: StreamConnectionState = .disconnected
    var receivedMessages: [StreamMessage] = []
    /// Time-to-first-byte after connect (ms). `nil` until first event arrives.
    var latencyMs: Int? = nil

    private var streamTask: Task<Void, Never>?
    private var session: URLSession?

    func connect(url: URL, headers: [String: String]) async throws {
        disconnect()
        state = .connecting

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: config)
        self.session = session

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        for (k, v) in headers where k.lowercased() != "accept" {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let connectStart = Date()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await session.bytes(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    await MainActor.run {
                        self.state = .error("HTTP \(http.statusCode)")
                    }
                    return
                }
                await MainActor.run { self.state = .connected }

                var eventName: String? = nil
                var dataLines: [String] = []
                var firstEvent = true

                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    if line.isEmpty {
                        // Dispatch
                        if !dataLines.isEmpty {
                            let payload = dataLines.joined(separator: "\n")
                            await MainActor.run {
                                if firstEvent {
                                    self.latencyMs = Int(Date().timeIntervalSince(connectStart) * 1000)
                                    firstEvent = false
                                }
                                self.receivedMessages.append(
                                    StreamMessage(
                                        direction: .incoming,
                                        text: payload,
                                        isBinary: false,
                                        eventName: eventName
                                    )
                                )
                            }
                        }
                        eventName = nil
                        dataLines.removeAll()
                        continue
                    }

                    // Comment lines start with ':' — ignore per spec.
                    if line.hasPrefix(":") { continue }

                    if let colon = line.firstIndex(of: ":") {
                        let field = String(line[..<colon])
                        var value = String(line[line.index(after: colon)...])
                        if value.hasPrefix(" ") { value.removeFirst() }
                        switch field {
                        case "event": eventName = value
                        case "data":  dataLines.append(value)
                        case "id", "retry": break
                        default: break
                        }
                    } else {
                        // Field with no value (rare).
                        if line == "data" { dataLines.append("") }
                    }
                }

                await MainActor.run {
                    if case .connected = self.state {
                        self.state = .disconnected
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        session?.invalidateAndCancel()
        session = nil
        if case .connecting = state {
            state = .disconnected
        } else if case .connected = state {
            state = .disconnected
        }
    }

    func clearMessages() {
        receivedMessages.removeAll()
    }
}
