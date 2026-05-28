import Foundation

/// A single frame exchanged over a streaming connection (WebSocket or SSE).
///
/// For WebSocket: covers both outgoing client frames and incoming server frames.
/// For SSE: only `.incoming` is used — SSE is server-push only.
struct StreamMessage: Identifiable, Hashable {
    let id: UUID
    let direction: Direction
    let timestamp: Date
    let text: String
    let isBinary: Bool
    /// Optional SSE event name (`event:` field). `nil` for WebSocket frames.
    let eventName: String?

    enum Direction: String, Hashable {
        case incoming
        case outgoing
    }

    init(
        id: UUID = UUID(),
        direction: Direction,
        timestamp: Date = Date(),
        text: String,
        isBinary: Bool = false,
        eventName: String? = nil
    ) {
        self.id = id
        self.direction = direction
        self.timestamp = timestamp
        self.text = text
        self.isBinary = isBinary
        self.eventName = eventName
    }
}
