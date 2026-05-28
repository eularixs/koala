import Foundation
import Observation
import NIO
import NIOHTTP1
import NIOPosix

// MARK: - UpstreamRule

struct UpstreamRule: Equatable, Codable, Identifiable {
    var id = UUID()
    var pathPrefix: String   // e.g. "/" or "/__auth"
    var upstream: URL

    private enum CodingKeys: String, CodingKey { case id, pathPrefix, upstream }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pathPrefix, forKey: .pathPrefix)
        try c.encode(upstream.absoluteString, forKey: .upstream)
    }

    init(id: UUID = UUID(), pathPrefix: String, upstream: URL) {
        self.id = id
        self.pathPrefix = pathPrefix
        self.upstream = upstream
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pathPrefix = try c.decode(String.self, forKey: .pathPrefix)
        let raw = try c.decode(String.self, forKey: .upstream)
        guard let url = URL(string: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .upstream, in: c, debugDescription: "bad URL")
        }
        upstream = url
    }
}

// MARK: - ProxyMode

enum ProxyMode: Equatable, Codable {
    case reverse(rules: [UpstreamRule])
    case forward

    private enum CodingKeys: String, CodingKey { case type, upstream, rules }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reverse(let rules):
            try c.encode("reverse", forKey: .type)
            try c.encode(rules, forKey: .rules)
        case .forward:
            try c.encode("forward", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        if type_ == "reverse" {
            // Try new multi-rule format first
            if let rules = try? c.decode([UpstreamRule].self, forKey: .rules), !rules.isEmpty {
                self = .reverse(rules: rules)
            } else if let rawURL = try? c.decode(String.self, forKey: .upstream),
                      let url = URL(string: rawURL) {
                // Migrate old single-upstream format → single-rule list
                self = .reverse(rules: [UpstreamRule(pathPrefix: "/", upstream: url)])
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .rules, in: c, debugDescription: "reverse mode requires rules or upstream"
                )
            }
        } else {
            self = .forward
        }
    }
}

// MARK: - CaptureFilter

struct CaptureFilter: Equatable, Codable {
    var skipStaticAssets: Bool = true
    var pathGlobs: [String] = []
    /// Domain allowlist. If non-empty, only captures whose host CONTAINS one of
    /// these strings are kept; everything else skipped. Empty = no host filter.
    /// Match is substring (so "eularix.com" matches "api.auth.eularix.com").
    var domainAllowlist: [String] = []

    private enum CodingKeys: String, CodingKey {
        case skipStaticAssets, pathGlobs, domainAllowlist
    }

    init(skipStaticAssets: Bool = true, pathGlobs: [String] = [], domainAllowlist: [String] = []) {
        self.skipStaticAssets = skipStaticAssets
        self.pathGlobs = pathGlobs
        self.domainAllowlist = domainAllowlist
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skipStaticAssets = (try? c.decode(Bool.self, forKey: .skipStaticAssets)) ?? true
        pathGlobs = (try? c.decode([String].self, forKey: .pathGlobs)) ?? []
        domainAllowlist = (try? c.decode([String].self, forKey: .domainAllowlist)) ?? []
    }
}

// MARK: - ProxyState

enum ProxyState: Equatable {
    case stopped
    case listening(port: UInt16)
    case error(String)

    var label: String {
        switch self {
        case .stopped:              return "Stopped"
        case .listening(let p):     return "Listening :\(p)"
        case .error(let msg):       return "Error: \(msg)"
        }
    }
}

// Hop-by-hop headers that must be stripped before forwarding.
// Global constant so nonisolated functions can access without MainActor hop.
private let proxyHopByHopHeaders: Set<String> = [
    "proxy-connection", "connection", "host", "keep-alive",
    "te", "trailers", "transfer-encoding", "upgrade", "content-length"
]

// MARK: - RecordingProxyService
//
// HTTP/HTTPS proxy built on SwiftNIO (ServerBootstrap + NIOHTTP1).
// HTTPS interception (MITM) uses KoalaRootCA-signed leaf certs via NIOSSLServerHandler.
//
// Modes
// -----
// .reverse(rules:)  – Zero-config UX. User browses http://localhost:PORT and
//                     Koala routes by path prefix to configured upstream URLs.
//                     Cookies, headers, body URLs are transparently rewritten.
// .forward          – Classic forward proxy. User configures system HTTP_PROXY
//                     → localhost:PORT. All HTTP traffic flows through here.
//
// Both modes capture request + response for replay/export.
//
// Captures are capped at 1000 entries (oldest dropped).
@MainActor
@Observable
final class RecordingProxyService {

    // MARK: State

    var state: ProxyState = .stopped
    var captures: [RecordedRequest] = []

    // MARK: Config (persisted to UserDefaults)

    var mode: ProxyMode {
        didSet { persistConfig() }
    }

    var port: UInt16 {
        didSet { persistConfig() }
    }

    var captureFilter: CaptureFilter {
        didSet { persistConfig() }
    }

    private static let maxCaptures = 1000
    private static let captureFile = "captures.json"

    private static let udKeyMode = "KoalaProxyMode"
    private static let udKeyPort = "KoalaProxyPort"
    private static let udKeyCaptureFilter = "KoalaCaptureFilter"

    private var group: EventLoopGroup?
    private var serverChannel: Channel?
    private let urlSession: URLSession

    // MARK: Init

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.urlSession = URLSession(configuration: config)

        // Load persisted config
        let savedPort = UserDefaults.standard.integer(forKey: Self.udKeyPort)
        self.port = savedPort > 0 ? UInt16(clamping: savedPort) : 8080

        if let data = UserDefaults.standard.data(forKey: Self.udKeyMode),
           let decoded = try? JSONDecoder().decode(ProxyMode.self, from: data) {
            self.mode = decoded
        } else {
            self.mode = .reverse(rules: [])
        }

        if let data = UserDefaults.standard.data(forKey: Self.udKeyCaptureFilter),
           let decoded = try? JSONDecoder().decode(CaptureFilter.self, from: data) {
            self.captureFilter = decoded
        } else {
            self.captureFilter = CaptureFilter()
        }

        loadFromDisk()
    }

    // MARK: Lifecycle

    /// Start listening. Uses `self.port` when `port` param is nil.
    func start(port overridePort: UInt16? = nil) throws {
        let listenPort = Int(overridePort ?? self.port)
        stop()

        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let weakSelf = self

        let bootstrap = ServerBootstrap(group: elg)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let decoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                let encoder = HTTPResponseEncoder()
                let handler = ProxyRequestHandler(service: weakSelf, httpDecoder: decoder, httpEncoder: encoder)
                return channel.pipeline.addHandlers([decoder, encoder, handler])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        do {
            let channel = try bootstrap.bind(host: "127.0.0.1", port: listenPort).wait()
            self.serverChannel = channel
            self.group = elg
            state = .listening(port: UInt16(listenPort))
        } catch {
            try? elg.syncShutdownGracefully()
            state = .error("Bind failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Backward-compat overload that matches the old explicit-port signature.
    func start(port: UInt16) throws {
        try start(port: Optional(port))
    }

    func stop() {
        try? serverChannel?.close().wait()
        try? group?.syncShutdownGracefully()
        serverChannel = nil
        group = nil
        if case .listening = state { state = .stopped }
    }

    // MARK: Capture management

    func clear() {
        captures.removeAll()
        persist()
    }

    func delete(_ id: UUID) {
        captures.removeAll { $0.id == id }
        persist()
    }

    // MARK: Save as Project

    @discardableResult
    func saveAsProject(name: String, into appState: AppState) -> Project {
        let projectName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? defaultProjectName()
            : name.trimmingCharacters(in: .whitespaces)

        let project = appState.createProject(name: projectName)
        let devTagId = appState.tags.first(where: { $0.name == "Development" })?.id
        if let devTagId {
            appState.setTag(devTagId, for: project.id)
        }

        let grouped = RequestGroupingEngine.group(captures)
        let collections = grouped.map { buildCollection(from: $0, projectId: project.id) }
        appState.insertCollections(collections, forProject: project.id)

        captures.removeAll()
        persist()
        return project
    }

    private func defaultProjectName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Recorded \(formatter.string(from: Date()))"
    }

    private func buildCollection(from group: GroupedCollection, projectId: UUID) -> KoalaCollection {
        let items: [CollectionItem] = group.requests.map { gr in
            let method = HTTPMethodValue.from(string: gr.method)
            let pathOnly: String = {
                guard let comps = URLComponents(string: gr.url) else { return gr.url }
                return comps.path.isEmpty ? "/" : comps.path
            }()
            let baseURL: String = {
                guard let comps = URLComponents(string: gr.url),
                      let scheme = comps.scheme,
                      let host = comps.host else { return gr.url }
                return "\(scheme)://\(host)\(pathOnly)"
            }()
            let req = KoalaRequest(
                name: "\(gr.method) \(gr.name)",
                method: method,
                url: baseURL,
                queryParams: gr.queryParams,
                headers: gr.headers,
                body: gr.requestBody
            )
            return .request(req)
        }
        return KoalaCollection(projectId: projectId, name: group.name, items: items)
    }

    // MARK: Config persistence (UserDefaults)

    private func persistConfig() {
        UserDefaults.standard.set(Int(port), forKey: Self.udKeyPort)
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: Self.udKeyMode)
        }
        if let data = try? JSONEncoder().encode(captureFilter) {
            UserDefaults.standard.set(data, forKey: Self.udKeyCaptureFilter)
        }
    }

    // MARK: - NIO request processing

    /// Central async entry point called by ProxyRequestHandler.
    /// Converts NIO HTTP types → upstream URLRequest → response → ProxyResult.
    func processHTTPRequest(head: HTTPRequestHead, body: ByteBuffer?, connectHost: String?) async -> ProxyResult {
        let started = Date()
        let currentMode = mode
        let currentPort = port
        let currentFilter = captureFilter

        // Build a ParsedRequest from NIO types for reuse of existing routing logic.
        let headerPairs: [(key: String, value: String)] = head.headers.map { ($0.name, $0.value) }
        let bodyData: Data? = body.flatMap { buf in
            var copy = buf
            guard let bytes = copy.readBytes(length: copy.readableBytes) else { return nil }
            return Data(bytes)
        }
        let parsed = ParsedRequest(
            method: head.method.rawValue,
            path: head.uri,
            httpVersion: "HTTP/\(head.version.major).\(head.version.minor)",
            headers: headerPairs,
            body: bodyData
        )

        // Resolve upstream URL — for CONNECT-tunnelled requests the URI is origin-form,
        // so pass connectHost so the forward resolver can reconstruct an absolute URL.
        guard let url = resolveUpstreamURL(from: parsed, mode: currentMode, connectHost: connectHost) else {
            return ProxyResult(status: 400, headers: ["Content-Length": "0", "Connection": "close"], body: [])
        }

        var req = URLRequest(url: url)
        req.httpMethod = parsed.method
        let rewrittenHeaders = rewriteRequestHeaders(parsed.headers, upstream: url, mode: currentMode)
        for (k, v) in rewrittenHeaders {
            // Override Accept-Encoding — URLSession only auto-decompresses gzip/deflate/br.
            // If client requested zstd, upstream may pick it and URLSession passes it through
            // raw; we then strip Content-Encoding and browser receives undecodable bytes.
            if k.lowercased() == "accept-encoding" { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        if let bodyData = parsed.body, !bodyData.isEmpty { req.httpBody = bodyData }

        do {
            let (data, response) = try await urlSession.data(for: req)
            let durationMs = Int(Date().timeIntervalSince(started) * 1000)

            let httpResp = response as? HTTPURLResponse
            let status = httpResp?.statusCode ?? 200
            var rawRespHeaders: [String: String] = [:]
            if let raw = httpResp?.allHeaderFields as? [String: String] {
                for (k, v) in raw {
                    let lower = k.lowercased()
                    if ["transfer-encoding", "connection", "keep-alive",
                        "content-encoding", "content-length",
                        "strict-transport-security",
                        "content-security-policy", "content-security-policy-report-only"].contains(lower) { continue }
                    rawRespHeaders[k] = v
                }
            }

            var respHeaders = rewriteResponseHeaders(rawRespHeaders, upstream: url, localPort: currentPort, mode: currentMode)
            let contentType = respHeaders.first(where: { $0.key.lowercased() == "content-type" })?.value ?? ""
            var bodyData = data
            if case .reverse(let rules) = currentMode {
                bodyData = rewriteBody(bodyData, contentType: contentType, rules: rules, localPort: currentPort)
            }
            respHeaders["Content-Length"] = "\(bodyData.count)"
            respHeaders["Connection"] = "close"

            var captureHeaders = respHeaders
            captureHeaders.removeValue(forKey: "Connection")
            record(parsed: parsed, url: url, status: status,
                   responseHeaders: captureHeaders, responseBody: bodyData,
                   durationMs: durationMs, captureFilter: currentFilter)

            return ProxyResult(status: status, headers: respHeaders, body: [UInt8](bodyData))

        } catch {
            let durationMs = Int(Date().timeIntervalSince(started) * 1000)
            let msg = "Upstream error: \(error.localizedDescription)"
            record(parsed: parsed, url: url, status: 502, responseHeaders: [:],
                   responseBody: msg.data(using: .utf8), durationMs: durationMs, captureFilter: currentFilter)
            return ProxyResult(
                status: 502,
                headers: ["Content-Length": "\(msg.utf8.count)", "Connection": "close"],
                body: [UInt8](msg.utf8)
            )
        }
    }

    // MARK: - URL resolution (extended for CONNECT context)

    nonisolated private func resolveUpstreamURL(from parsed: ParsedRequest, mode: ProxyMode, connectHost: String?) -> URL? {
        // If we have a CONNECT context host, resolve forward-mode with that host injected.
        if let connectHost, case .forward = mode {
            return resolveForwardURLWithHost(from: parsed, connectHost: connectHost)
        }
        return resolveUpstreamURL(from: parsed, mode: mode)
    }

    /// Forward URL resolution when the connection came through CONNECT (MITM path).
    /// head.uri is origin-form (e.g. "/api/users"), connectHost is "api.example.com".
    nonisolated private func resolveForwardURLWithHost(from parsed: ParsedRequest, connectHost: String) -> URL? {
        let path = parsed.path.isEmpty ? "/" : parsed.path
        // Use HTTPS as the scheme since the client connected via CONNECT (TLS intent)
        return URL(string: "https://\(connectHost)\(path)")
    }

    // MARK: - URL resolution

    /// Determines the upstream URL to forward the request to.
    nonisolated fileprivate func resolveUpstreamURL(from parsed: ParsedRequest, mode: ProxyMode) -> URL? {
        switch mode {
        case .reverse(let rules):
            return resolveReverseURL(from: parsed, rules: rules)
        case .forward:
            return resolveForwardURL(from: parsed)
        }
    }

    nonisolated fileprivate func resolveReverseURL(from parsed: ParsedRequest, rules: [UpstreamRule]) -> URL? {
        // Extract path (strip query string for prefix matching)
        let pathAndQuery = parsed.path
        let path: String
        if let qIdx = pathAndQuery.firstIndex(of: "?") {
            path = String(pathAndQuery[..<qIdx])
        } else {
            path = pathAndQuery.isEmpty ? "/" : pathAndQuery
        }

        // Sort by prefix length descending — longest prefix wins
        let sorted = rules.sorted { $0.pathPrefix.count > $1.pathPrefix.count }
        guard let rule = sorted.first(where: { pathMatchesPrefix(path, prefix: $0.pathPrefix) }) else {
            return nil
        }

        return buildUpstreamURL(pathAndQuery: pathAndQuery, rule: rule)
    }

    /// Returns true if `path` starts with `prefix`.
    /// "/" always matches. "/__auth" matches "/__auth" and "/__auth/foo" but not "/__authz".
    nonisolated fileprivate func pathMatchesPrefix(_ path: String, prefix: String) -> Bool {
        if prefix == "/" { return true }
        if path == prefix { return true }
        return path.hasPrefix(prefix + "/") || path.hasPrefix(prefix + "?")
    }

    /// Strip matched prefix from path and append remainder to upstream base.
    nonisolated private func buildUpstreamURL(pathAndQuery: String, rule: UpstreamRule) -> URL? {
        let prefix = rule.pathPrefix
        var comps = URLComponents(url: rule.upstream, resolvingAgainstBaseURL: false)

        // Separate path from query
        let rawPath: String
        let rawQuery: String?
        if let qIdx = pathAndQuery.firstIndex(of: "?") {
            rawPath = String(pathAndQuery[..<qIdx])
            rawQuery = String(pathAndQuery[pathAndQuery.index(after: qIdx)...])
        } else {
            rawPath = pathAndQuery.isEmpty ? "/" : pathAndQuery
            rawQuery = nil
        }

        // Strip prefix from path
        let remainder: String
        if prefix == "/" {
            remainder = rawPath
        } else if rawPath == prefix {
            remainder = ""
        } else {
            // rawPath starts with prefix + "/"
            remainder = String(rawPath.dropFirst(prefix.count))
        }

        // Combine upstream base path with remainder (avoid double slash)
        let upstreamBasePath = (comps?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if upstreamBasePath.isEmpty {
            comps?.path = remainder.isEmpty ? "/" : (remainder.hasPrefix("/") ? remainder : "/\(remainder)")
        } else {
            let rem = remainder.hasPrefix("/") ? remainder : (remainder.isEmpty ? "" : "/\(remainder)")
            comps?.path = "/\(upstreamBasePath)\(rem)"
        }

        comps?.query = rawQuery
        return comps?.url
    }

    nonisolated private func resolveForwardURL(from parsed: ParsedRequest) -> URL? {
        // Forward proxy: client sends absolute URL on request line, or origin-form + Host header.
        if let u = URL(string: parsed.path), let scheme = u.scheme, !scheme.isEmpty {
            return u
        }
        if let host = parsed.headers.first(where: { $0.key.lowercased() == "host" })?.value {
            return URL(string: "http://\(host)\(parsed.path)")
        }
        return nil
    }

    // MARK: - Header rewriting

    /// Rewrite request headers for forwarding.
    nonisolated func rewriteRequestHeaders(
        _ headers: [(String, String)],
        upstream: URL,
        mode: ProxyMode
    ) -> [(String, String)] {
        // Origin/Referer should map to the FRONTEND page origin (catch-all "/" rule's upstream),
        // not the per-request backend upstream. Backend CORS check expects the frontend domain.
        let originUpstream: URL = {
            if case .reverse(let rules) = mode {
                if let catchAll = rules.first(where: { $0.pathPrefix == "/" }) {
                    return catchAll.upstream
                }
                // No catch-all → fall back to longest-prefix rule's upstream
                if let longest = rules.max(by: { $0.pathPrefix.count < $1.pathPrefix.count }) {
                    return longest.upstream
                }
            }
            return upstream
        }()

        var out: [(String, String)] = []
        for (k, v) in headers {
            let lower = k.lowercased()
            if proxyHopByHopHeaders.contains(lower) { continue }

            switch mode {
            case .reverse:
                if lower == "origin" {
                    out.append((k, rewriteLocalToUpstream(v, upstream: originUpstream)))
                } else if lower == "referer" {
                    out.append((k, rewriteLocalToUpstream(v, upstream: originUpstream)))
                } else {
                    out.append((k, v))
                }
            case .forward:
                out.append((k, v))
            }
        }

        // In reverse mode, set Host to per-request upstream host (HTTP/1.1 spec)
        if case .reverse = mode, let host = upstream.host {
            let hostValue = upstream.port != nil ? "\(host):\(upstream.port!)" : host
            out.append(("Host", hostValue))
        }

        return out
    }

    /// Replace `http://localhost:PORT` or `http://127.0.0.1:PORT` (+ https variants)
    /// in a header value with the upstream origin.
    nonisolated private func rewriteLocalToUpstream(_ value: String, upstream: URL) -> String {
        guard let upstreamScheme = upstream.scheme, let upstreamHost = upstream.host else {
            return value
        }
        let upstreamOrigin = upstreamHost.contains(":") ? "\(upstreamScheme)://[\(upstreamHost)]" : "\(upstreamScheme)://\(upstreamHost)"
        let prefixes = [
            "http://localhost", "https://localhost",
            "http://127.0.0.1", "https://127.0.0.1",
            "http://0.0.0.0", "https://0.0.0.0",
        ]
        for prefix in prefixes {
            if value.hasPrefix(prefix) {
                let afterScheme = value.dropFirst(prefix.count)
                if afterScheme.hasPrefix(":") {
                    let afterPort = afterScheme.drop(while: { $0 == ":" || $0.isNumber })
                    return upstreamOrigin + afterPort
                } else {
                    return upstreamOrigin + afterScheme
                }
            }
        }
        return value
    }

    /// Rewrite response headers: strip/rewrite Set-Cookie, rewrite Location.
    nonisolated func rewriteResponseHeaders(
        _ headers: [String: String],
        upstream: URL,
        localPort: UInt16,
        mode: ProxyMode
    ) -> [String: String] {
        guard case .reverse = mode else { return headers }
        var out: [String: String] = [:]
        for (k, v) in headers {
            let lower = k.lowercased()
            if lower == "set-cookie" {
                // HTTPURLResponse merges multiple Set-Cookie with ", " — split carefully.
                let cookies = splitSetCookieHeader(v)
                let rewritten = cookies.map { rewriteSetCookie($0) }.joined(separator: ", ")
                out[k] = rewritten
            } else if lower == "location" {
                out[k] = rewriteLocation(v, upstream: upstream)
            } else {
                out[k] = v
            }
        }
        return out
    }

    /// Split a merged Set-Cookie header value into individual cookie strings.
    /// The tricky part: commas inside expires= date values (e.g. "Thu, 01 Jan 2099")
    /// are NOT separators. A separator comma is followed by a space and then `token=`.
    nonisolated func splitSetCookieHeader(_ merged: String) -> [String] {
        var results: [String] = []
        var current = ""
        let chars = Array(merged)
        var i = 0
        while i < chars.count {
            if chars[i] == "," {
                // Look ahead: skip space(s), check if next token contains "="
                var j = i + 1
                while j < chars.count && chars[j] == " " { j += 1 }
                // Collect the next word
                var word = ""
                while j < chars.count && chars[j] != "=" && chars[j] != ";" && chars[j] != "," {
                    word.append(chars[j]); j += 1
                }
                let isNewCookie = j < chars.count && chars[j] == "=" && !word.isEmpty
                if isNewCookie {
                    results.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    i += 1
                    continue
                }
            }
            current.append(chars[i])
            i += 1
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            results.append(current.trimmingCharacters(in: .whitespaces))
        }
        return results.isEmpty ? [merged] : results
    }

    /// Strip Domain, Secure; remap SameSite=Strict → SameSite=Lax for localhost compatibility.
    nonisolated func rewriteSetCookie(_ cookieStr: String) -> String {
        var parts = cookieStr.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        parts = parts.filter { part in
            let lower = part.lowercased()
            if lower.hasPrefix("domain=") { return false }
            if lower == "secure" { return false }
            return true
        }
        // Remap SameSite=Strict → SameSite=Lax
        parts = parts.map { part in
            if part.lowercased() == "samesite=strict" { return "SameSite=Lax" }
            return part
        }
        return parts.joined(separator: "; ")
    }

    /// Rewrite Location header: absolute upstream URL → relative path.
    nonisolated func rewriteLocation(_ value: String, upstream: URL) -> String {
        guard let loc = URL(string: value),
              let locHost = loc.host,
              let upstreamHost = upstream.host,
              locHost == upstreamHost else {
            return value
        }
        // Same host → make relative
        var rel = loc.path
        if rel.isEmpty { rel = "/" }
        if let q = loc.query { rel += "?\(q)" }
        if let frag = loc.fragment { rel += "#\(frag)" }
        return rel
    }

    // MARK: - Body rewriting

    /// Replace all upstream URLs in text response bodies with localhost equivalents.
    /// Rewrites longer/more-specific upstreams first to avoid partial substring matches.
    nonisolated func rewriteBody(_ data: Data, contentType: String, rules: [UpstreamRule], localPort: UInt16) -> Data {
        let rewritableTypes = ["text/html", "text/css", "application/json",
                               "application/javascript", "text/javascript"]
        let ct = contentType.lowercased()
        guard rewritableTypes.contains(where: { ct.hasPrefix($0) }) else { return data }
        guard data.count <= 5 * 1024 * 1024 else { return data }
        guard var text = String(data: data, encoding: .utf8) else { return data }

        // Sort rules so we rewrite longer/more-specific upstreams first
        let sorted = rules.sorted { a, b in
            let aHost = a.upstream.host ?? ""
            let bHost = b.upstream.host ?? ""
            return aHost.count > bHost.count
        }

        for rule in sorted {
            guard let upstreamHost = rule.upstream.host else { continue }
            let upstreamScheme = rule.upstream.scheme ?? "https"
            let localPrefix = rule.pathPrefix == "/" ? "" : rule.pathPrefix

            // Rewrite scheme://host[:port] → http://localhost:PORT<prefix>
            let upstreamFull: String = {
                if let p = rule.upstream.port { return "\(upstreamScheme)://\(upstreamHost):\(p)" }
                return "\(upstreamScheme)://\(upstreamHost)"
            }()
            let localFull = "http://localhost:\(localPort)\(localPrefix)"
            text = text.replacingOccurrences(of: upstreamFull, with: localFull)

            // Rewrite scheme-less //host[:port] → //localhost:PORT<prefix>
            let schemeRelative: String = {
                if let p = rule.upstream.port { return "//\(upstreamHost):\(p)" }
                return "//\(upstreamHost)"
            }()
            text = text.replacingOccurrences(of: schemeRelative, with: "//localhost:\(localPort)\(localPrefix)")
        }

        return text.data(using: .utf8) ?? data
    }

    // MARK: - Capture filter

    nonisolated fileprivate func isStaticAsset(_ contentType: String) -> Bool {
        let lower = contentType.lowercased()
        let patterns = ["text/html", "text/css", "application/javascript",
                        "text/javascript", "image/", "font/", "video/",
                        "audio/", "application/font-", "application/x-font-",
                        "text/event-stream-static"]
        return patterns.contains { lower.hasPrefix($0) }
    }

    nonisolated fileprivate func pathMatchesGlob(_ path: String, glob: String) -> Bool {
        // Convert glob to NSPredicate LIKE pattern
        // "**" → matches any sequence including "/"
        // "*" → matches any sequence not including "/"
        // We replace ** first, then * for single-segment
        let escaped = glob
            .replacingOccurrences(of: "**", with: "\u{0001}")  // temp placeholder
            .replacingOccurrences(of: "*", with: "[^/]*")
            .replacingOccurrences(of: "\u{0001}", with: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$") else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    nonisolated fileprivate func shouldCapture(
        host: String,
        path: String,
        contentType: String,
        filter: CaptureFilter
    ) -> Bool {
        // Domain allowlist: substring match. If non-empty, host MUST match.
        if !filter.domainAllowlist.isEmpty {
            let hostLower = host.lowercased()
            let matchesDomain = filter.domainAllowlist.contains { needle in
                let n = needle.trimmingCharacters(in: .whitespaces).lowercased()
                return !n.isEmpty && hostLower.contains(n)
            }
            if !matchesDomain { return false }
        }
        if filter.skipStaticAssets && isStaticAsset(contentType) { return false }
        if !filter.pathGlobs.isEmpty {
            return filter.pathGlobs.contains { pathMatchesGlob(path, glob: $0) }
        }
        return true
    }

    // MARK: - Record

    private func record(
        parsed: ParsedRequest,
        url: URL,
        status: Int,
        responseHeaders: [String: String],
        responseBody: Data?,
        durationMs: Int,
        captureFilter: CaptureFilter = CaptureFilter()
    ) {
        let contentType = responseHeaders.first(where: { $0.key.lowercased() == "content-type" })?.value ?? ""
        let requestPath = url.path.isEmpty ? "/" : url.path

        let host = url.host ?? ""
        guard shouldCapture(host: host, path: requestPath, contentType: contentType, filter: captureFilter) else {
            return
        }

        var headers: [String: String] = [:]
        for (k, v) in parsed.headers { headers[k] = v }
        let entry = RecordedRequest(
            method: parsed.method,
            url: url.absoluteString,
            headers: headers,
            requestBody: parsed.body,
            responseStatus: status,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            durationMs: durationMs,
            host: url.host ?? "unknown"
        )
        captures.insert(entry, at: 0)
        if captures.count > Self.maxCaptures {
            captures = Array(captures.prefix(Self.maxCaptures))
        }
        persist()
    }

    // MARK: Persistence (DB agent owns these — DO NOT MODIFY)

    private var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Koala").appendingPathComponent("recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.captureFile)
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoded = try JSONDecoder().decode([RecordedRequest].self, from: data)
            self.captures = decoded
        } catch {
            self.captures = []
        }
    }

    private func persist() {
        let snapshot = captures
        let url = storeURL
        Task.detached {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                // Best-effort persistence; ignore.
            }
        }
    }
}

// MARK: - Testing surface
// These wrappers expose internal logic for unit tests without leaking ParsedRequest.

extension RecordingProxyService {
    /// Resolve upstream URL from a raw path string (for unit testing).
    nonisolated func resolveUpstream(path: String, rules: [UpstreamRule]) -> URL? {
        let parsed = ParsedRequest(method: "GET", path: path, httpVersion: "HTTP/1.1", headers: [], body: nil)
        return resolveReverseURL(from: parsed, rules: rules)
    }

    /// Public wrapper for pathMatchesPrefix (for unit testing).
    nonisolated func testPathMatchesPrefix(_ path: String, prefix: String) -> Bool {
        pathMatchesPrefix(path, prefix: prefix)
    }

    /// Rewrite body with multi-upstream rules (for unit testing).
    nonisolated func rewriteBodyMulti(_ data: Data, contentType: String, rules: [UpstreamRule], localPort: UInt16) -> Data {
        rewriteBody(data, contentType: contentType, rules: rules, localPort: localPort)
    }

    /// Check if path+contentType should be captured under given filter (for unit testing).
    nonisolated func testShouldCapture(path: String, contentType: String, filter: CaptureFilter) -> Bool {
        shouldCapture(host: "", path: path, contentType: contentType, filter: filter)
    }

    /// Check with explicit host (for unit testing domain allowlist).
    nonisolated func testShouldCapture(host: String, path: String, contentType: String, filter: CaptureFilter) -> Bool {
        shouldCapture(host: host, path: path, contentType: contentType, filter: filter)
    }

    /// Check if content type is a static asset (for unit testing).
    nonisolated func testIsStaticAsset(_ contentType: String) -> Bool {
        isStaticAsset(contentType)
    }

    /// Check if path matches glob (for unit testing).
    nonisolated func testPathMatchesGlob(_ path: String, glob: String) -> Bool {
        pathMatchesGlob(path, glob: glob)
    }
}

// MARK: - ParsedRequest

private struct ParsedRequest: @unchecked Sendable {
    var method: String
    /// Either absolute URL (proxy-form) or origin-form path.
    var path: String
    var httpVersion: String
    var headers: [(key: String, value: String)]
    var body: Data?

    static func parse(headerString: String) -> ParsedRequest? {
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3 else { return nil }

        var headers: [(String, String)] = []
        for line in lines.dropFirst() where !line.isEmpty {
            if let idx = line.firstIndex(of: ":") {
                let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers.append((k, v))
            }
        }
        return ParsedRequest(method: parts[0], path: parts[1], httpVersion: parts[2], headers: headers, body: nil)
    }
}

// MARK: - ProxyResult

struct ProxyResult {
    let status: Int
    let headers: [String: String]
    let body: [UInt8]
}

// MARK: - ProxyError

enum ProxyError: Error, LocalizedError {
    case invalidPort
    case badRequest
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:          return "Invalid proxy port."
        case .badRequest:           return "Malformed HTTP request from client."
        case .upstream(let m):      return "Upstream error: \(m)"
        }
    }
}
