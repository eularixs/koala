import SwiftUI

struct StatusBadgeView: View {
    let statusCode: Int

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced).monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    private var label: String {
        if let text = Self.knownCodes[statusCode] {
            return "\(statusCode) \(text)"
        }
        return "\(statusCode)"
    }

    private var color: Color {
        switch statusCode {
        case 100..<200: return .gray
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default:        return .gray
        }
    }

    private static let knownCodes: [Int: String] = [
        100: "Continue",
        101: "Switching Protocols",
        200: "OK",
        201: "Created",
        202: "Accepted",
        204: "No Content",
        206: "Partial Content",
        301: "Moved Permanently",
        302: "Found",
        304: "Not Modified",
        307: "Temporary Redirect",
        308: "Permanent Redirect",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        408: "Request Timeout",
        409: "Conflict",
        410: "Gone",
        413: "Payload Too Large",
        415: "Unsupported Media Type",
        422: "Unprocessable Entity",
        429: "Too Many Requests",
        500: "Internal Server Error",
        501: "Not Implemented",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout",
    ]
}

// MARK: - Preview

#Preview("StatusBadgeView") {
    let codes = [200, 201, 204, 301, 304, 400, 401, 403, 404, 422, 429, 500, 502, 503]
    return VStack(alignment: .leading, spacing: 8) {
        ForEach(codes, id: \.self) { code in
            StatusBadgeView(statusCode: code)
        }
    }
    .padding()
}
