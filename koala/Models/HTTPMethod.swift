import SwiftUI

enum HTTPMethod: String, Codable, CaseIterable, Identifiable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
    case connect = "CONNECT"
    case trace = "TRACE"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .get:     return .blue
        case .post:    return .green
        case .put:     return .orange
        case .patch:   return Color(red: 0.6, green: 0.4, blue: 0.8)
        case .delete:  return .red
        case .head:    return .teal
        case .options: return .gray
        case .connect: return .brown
        case .trace:   return .pink
        }
    }
}

/// Extends HTTPMethod to support arbitrary custom verbs (e.g. "PURGE", "COPY"),
/// as well as non-REST streaming connections (WebSocket, Server-Sent Events).
enum HTTPMethodValue: Codable, Hashable {
    case standard(HTTPMethod)
    case custom(String)
    case websocket
    case sse

    var rawValue: String {
        switch self {
        case .standard(let m): return m.rawValue
        case .custom(let s):   return s.uppercased()
        case .websocket:       return "WS"
        case .sse:             return "SSE"
        }
    }

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .standard(let m): return m.color
        case .custom:          return .secondary
        case .websocket:       return .cyan
        case .sse:             return Color(red: 0.6, green: 0.3, blue: 0.85)
        }
    }

    /// True when this method represents a long-lived streaming connection
    /// (WebSocket / SSE) rather than a one-shot REST request.
    var isStreaming: Bool {
        switch self {
        case .websocket, .sse: return true
        default:               return false
        }
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let upper = raw.uppercased()
        switch upper {
        case "WS", "WEBSOCKET":
            self = .websocket
        case "SSE":
            self = .sse
        default:
            if let method = HTTPMethod(rawValue: upper) {
                self = .standard(method)
            } else {
                self = .custom(raw)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Convenience factory for building from a plain method string (e.g. from proxy captures).
    static func from(string: String) -> HTTPMethodValue {
        let upper = string.uppercased()
        switch upper {
        case "WS", "WEBSOCKET": return .websocket
        case "SSE":             return .sse
        default:
            if let m = HTTPMethod(rawValue: upper) { return .standard(m) }
            return .custom(string)
        }
    }
}
