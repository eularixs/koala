import Foundation

// MARK: - KoalaCookie

/// An HTTP cookie captured from a response or manually authored.
///
/// Persisted per-environment by `CookieJarService`. Domain matching follows
/// RFC 6265 (exact match, or suffix match if the stored domain begins with a dot).
struct KoalaCookie: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var value: String
    var domain: String
    /// Defaults to `"/"`.
    var path: String
    /// `nil` = session cookie (cleared when the session ends).
    var expires: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool
    /// `"Strict"`, `"Lax"`, `"None"`, or nil.
    var sameSite: String?
    var capturedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expires: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        sameSite: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
        self.capturedAt = capturedAt
    }

    /// Composite identity used by `CookieJarService` to determine whether an
    /// incoming cookie replaces an existing one (RFC 6265 §5.3).
    var storageKey: String {
        "\(name)\u{1}\(domain.lowercased())\u{1}\(path)"
    }

    var isExpired: Bool {
        guard let expires else { return false }
        return expires <= Date()
    }
}

// MARK: - Parsing

extension KoalaCookie {

    /// Parses a single `Set-Cookie` header value into one or more `KoalaCookie`s.
    ///
    /// Handles the RFC 6265 minimum:
    /// `Name=Value; Domain=; Path=; Expires=; Max-Age=; Secure; HttpOnly; SameSite=`
    ///
    /// `defaultDomain` is used when the header omits `Domain=` — typically the
    /// host of the request URL the response came from.
    ///
    /// - Note: HTTP allows servers to send multiple `Set-Cookie` headers, and
    ///   Foundation often merges them into one comma-joined string. We try a
    ///   best-effort split that respects the `Expires=...` comma. Callers that
    ///   have access to the raw header list should prefer feeding each header
    ///   value individually.
    static func parse(setCookieHeader header: String, defaultDomain: String) -> [KoalaCookie] {
        let cookieStrings = splitMergedSetCookies(header)
        return cookieStrings.compactMap { parseSingle($0, defaultDomain: defaultDomain) }
    }

    // MARK: Private parsing helpers

    private static func parseSingle(_ raw: String, defaultDomain: String) -> KoalaCookie? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ";", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let nameValueRaw = parts.first else { return nil }

        // Name=Value (value may itself contain '='; only split on the first).
        guard let eqIndex = nameValueRaw.firstIndex(of: "=") else { return nil }
        let name = String(nameValueRaw[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        var value = String(nameValueRaw[nameValueRaw.index(after: eqIndex)...])
        // Strip surrounding double-quotes if present.
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        guard !name.isEmpty else { return nil }

        var domain = defaultDomain.lowercased()
        var path = "/"
        var expires: Date? = nil
        var maxAge: Int? = nil
        var isSecure = false
        var isHTTPOnly = false
        var sameSite: String? = nil

        for attr in parts.dropFirst() {
            if let eq = attr.firstIndex(of: "=") {
                let k = attr[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                let v = attr[attr.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                switch k {
                case "domain":
                    let d = v.lowercased()
                    if !d.isEmpty { domain = d }
                case "path":
                    if !v.isEmpty { path = v }
                case "expires":
                    expires = parseExpires(String(v))
                case "max-age":
                    maxAge = Int(v)
                case "samesite":
                    let s = v.lowercased()
                    switch s {
                    case "strict": sameSite = "Strict"
                    case "lax":    sameSite = "Lax"
                    case "none":   sameSite = "None"
                    default:       sameSite = String(v)
                    }
                default:
                    break
                }
            } else {
                switch attr.lowercased() {
                case "secure":   isSecure = true
                case "httponly": isHTTPOnly = true
                default: break
                }
            }
        }

        // Max-Age overrides Expires per RFC 6265.
        if let maxAge {
            expires = Date().addingTimeInterval(TimeInterval(maxAge))
        }

        return KoalaCookie(
            name: name,
            value: value,
            domain: domain,
            path: path,
            expires: expires,
            isSecure: isSecure,
            isHTTPOnly: isHTTPOnly,
            sameSite: sameSite
        )
    }

    private static let expiresFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",   // RFC 1123
            "EEE, dd-MMM-yyyy HH:mm:ss zzz",   // Netscape
            "EEE MMM d HH:mm:ss yyyy"          // asctime
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "GMT")
            f.dateFormat = fmt
            return f
        }
    }()

    private static func parseExpires(_ s: String) -> Date? {
        for f in expiresFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Splits a header value that may contain multiple cookies joined by ", "
    /// (Foundation's `allHTTPHeaderFields` merges duplicate `Set-Cookie`s this way).
    /// Conservative: only splits on a comma that is followed by a token that
    /// looks like `name=` rather than a weekday inside `Expires=`.
    private static func splitMergedSetCookies(_ header: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(header)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "," {
                // Look ahead: skip optional whitespace, then see if we hit `token=`
                var j = i + 1
                while j < chars.count, chars[j] == " " { j += 1 }
                // Read potential token
                var k = j
                while k < chars.count, chars[k].isLetter || chars[k].isNumber
                      || chars[k] == "_" || chars[k] == "-" || chars[k] == "." || chars[k] == "!"
                      || chars[k] == "#" || chars[k] == "$" || chars[k] == "%" || chars[k] == "&"
                      || chars[k] == "'" || chars[k] == "*" || chars[k] == "+" || chars[k] == "^"
                      || chars[k] == "`" || chars[k] == "|" || chars[k] == "~" {
                    k += 1
                }
                if k > j && k < chars.count && chars[k] == "=" {
                    // Boundary between cookies.
                    result.append(current)
                    current = ""
                    i = j
                    continue
                }
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
