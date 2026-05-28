import Foundation
import Observation

/// Per-environment HTTP cookie jar.
///
/// # Integration (for the caller wiring requests)
///
/// On send:
/// ```
/// let envId = appState.selectedEnvironmentId
/// let cookieHeader: String? = envId.flatMap {
///     cookieJar.headerValueMatching(url: requestURL, forEnv: $0)
/// }
/// let response = try await httpClient.send(
///     request,
///     environment: env,
///     globalVariables: globals,
///     cookieHeader: cookieHeader
/// )
/// ```
///
/// On receive — feed each raw `Set-Cookie` header value back in:
/// ```
/// if let envId {
///     for rawSetCookie in response.rawSetCookieHeaders {
///         cookieJar.ingest(setCookieHeader: rawSetCookie,
///                          requestURL: requestURL,
///                          forEnv: envId)
///     }
/// }
/// ```
///
/// `CookieJarService` is `@MainActor` `@Observable`; treat it like other view-model
/// services and inject through the state container.
@MainActor
@Observable
final class CookieJarService {

    // MARK: Storage

    private var cookiesByEnv: [UUID: [KoalaCookie]] = [:]
    private let persistence: PersistenceService

    init(persistence: PersistenceService = PersistenceService()) {
        self.persistence = persistence
    }

    // MARK: Reads

    /// All non-expired cookies for the given environment (loads from disk lazily).
    func cookies(forEnv envId: UUID) -> [KoalaCookie] {
        ensureLoaded(envId)
        return (cookiesByEnv[envId] ?? []).filter { !$0.isExpired }
    }

    /// Cookies matching the URL per RFC 6265:
    /// - domain matches (exact, or stored domain has leading `.` and is a suffix)
    /// - path is a prefix of URL path
    /// - not expired
    /// - if cookie is `Secure`, URL must be `https`
    func cookiesMatching(url: URL, forEnv envId: UUID) -> [KoalaCookie] {
        ensureLoaded(envId)
        guard let host = url.host?.lowercased() else { return [] }
        let urlPath = url.path.isEmpty ? "/" : url.path
        let isHTTPS = (url.scheme?.lowercased() == "https")
        let now = Date()

        return (cookiesByEnv[envId] ?? []).filter { cookie in
            if let exp = cookie.expires, exp <= now { return false }
            if cookie.isSecure && !isHTTPS { return false }
            if !pathMatches(cookiePath: cookie.path, requestPath: urlPath) { return false }
            return domainMatches(cookieDomain: cookie.domain, host: host)
        }
    }

    /// Combined `Cookie:` header value (`a=1; b=2`) for the given URL, or nil
    /// when there is nothing to send.
    func headerValueMatching(url: URL, forEnv envId: UUID) -> String? {
        let matches = cookiesMatching(url: url, forEnv: envId)
        guard !matches.isEmpty else { return nil }
        // RFC 6265 ordering: longer path first, then earlier creation.
        let sorted = matches.sorted { lhs, rhs in
            if lhs.path.count != rhs.path.count { return lhs.path.count > rhs.path.count }
            return lhs.capturedAt < rhs.capturedAt
        }
        return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    // MARK: Mutations

    /// Replaces an existing cookie with the same `storageKey` (name+domain+path)
    /// or appends.
    func addOrUpdate(_ cookie: KoalaCookie, forEnv envId: UUID) {
        ensureLoaded(envId)
        var list = cookiesByEnv[envId] ?? []
        if let idx = list.firstIndex(where: { $0.storageKey == cookie.storageKey }) {
            // Preserve original id so persisted UI selection stays stable.
            var replacement = cookie
            replacement.id = list[idx].id
            list[idx] = replacement
        } else {
            list.append(cookie)
        }
        cookiesByEnv[envId] = list
        persist(envId)
    }

    func delete(_ id: UUID, forEnv envId: UUID) {
        ensureLoaded(envId)
        cookiesByEnv[envId]?.removeAll { $0.id == id }
        persist(envId)
    }

    func clear(forEnv envId: UUID) {
        cookiesByEnv[envId] = []
        persist(envId)
    }

    /// Convenience: parse a raw `Set-Cookie` header and ingest each resulting
    /// cookie. `requestURL` supplies the default domain when the header omits one.
    func ingest(setCookieHeader header: String, requestURL: URL, forEnv envId: UUID) {
        let defaultDomain = requestURL.host?.lowercased() ?? ""
        let parsed = KoalaCookie.parse(setCookieHeader: header, defaultDomain: defaultDomain)
        for cookie in parsed {
            addOrUpdate(cookie, forEnv: envId)
        }
    }

    /// Drops all on-disk + in-memory cookies for a deleted environment.
    func purge(envId: UUID) {
        cookiesByEnv.removeValue(forKey: envId)
        try? persistence.deleteCookies(forEnv: envId)
    }

    // MARK: Private

    private func ensureLoaded(_ envId: UUID) {
        if cookiesByEnv[envId] == nil {
            cookiesByEnv[envId] = (try? persistence.loadCookies(forEnv: envId)) ?? []
        }
    }

    private func persist(_ envId: UUID) {
        try? persistence.saveCookies(cookiesByEnv[envId] ?? [], forEnv: envId)
    }

    // MARK: RFC 6265 matching

    private func domainMatches(cookieDomain: String, host: String) -> Bool {
        let cd = cookieDomain.lowercased()
        let normalized = cd.hasPrefix(".") ? String(cd.dropFirst()) : cd
        if host == normalized { return true }
        // Suffix match only when the cookie domain originally allowed it, OR
        // we synthesised it from the request host (no dot). Per RFC 6265 the
        // common behaviour is: a cookie with explicit Domain attribute is
        // sent to subdomains; one without is host-only. We don't track that
        // distinction here, so allow suffix match guarded by a label boundary.
        if host.hasSuffix("." + normalized) { return true }
        return false
    }

    private func pathMatches(cookiePath: String, requestPath: String) -> Bool {
        if cookiePath == requestPath { return true }
        if requestPath.hasPrefix(cookiePath) {
            if cookiePath.hasSuffix("/") { return true }
            // Boundary character must follow.
            let nextIdx = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
            if nextIdx < requestPath.endIndex && requestPath[nextIdx] == "/" { return true }
        }
        return false
    }
}
