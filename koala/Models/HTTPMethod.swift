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

/// Extends HTTPMethod to support arbitrary custom verbs (e.g. "PURGE", "COPY").
/// Use `.standard` for the common cases and `.custom` when the verb is not in the enum.
enum HTTPMethodValue: Codable, Hashable {
    case standard(HTTPMethod)
    case custom(String)

    var rawValue: String {
        switch self {
        case .standard(let m): return m.rawValue
        case .custom(let s):   return s.uppercased()
        }
    }

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .standard(let m): return m.color
        case .custom:          return .secondary
        }
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let method = HTTPMethod(rawValue: raw.uppercased()) {
            self = .standard(method)
        } else {
            self = .custom(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
