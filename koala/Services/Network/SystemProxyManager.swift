import Foundation
import Observation
import SystemConfiguration
import Security

/// Manages macOS system-wide HTTP/HTTPS proxy via SystemConfiguration framework.
/// Uses `SCPreferencesCreateWithAuthorization` + `SCPreferencesCommitChanges` which
/// triggers macOS's native Touch ID / password sheet (same one used by Network panel).
@MainActor
@Observable
final class SystemProxyManager {

    enum State: Equatable {
        case unknown
        case off
        case on(host: String, port: UInt16)
        case error(String)
    }

    private(set) var state: State = .unknown

    init() {}

    // MARK: - Public API

    func enable(host: String = "127.0.0.1", port: UInt16) async throws {
        try mutateProxies { dict in
            dict[kCFNetworkProxiesHTTPEnable] = 1 as CFNumber
            dict[kCFNetworkProxiesHTTPProxy] = host as CFString
            dict[kCFNetworkProxiesHTTPPort] = port as CFNumber
            dict[kCFNetworkProxiesHTTPSEnable] = 1 as CFNumber
            dict[kCFNetworkProxiesHTTPSProxy] = host as CFString
            dict[kCFNetworkProxiesHTTPSPort] = port as CFNumber
        }
        state = .on(host: host, port: port)
    }

    func disable() async throws {
        try mutateProxies { dict in
            dict[kCFNetworkProxiesHTTPEnable] = 0 as CFNumber
            dict[kCFNetworkProxiesHTTPSEnable] = 0 as CFNumber
        }
        state = .off
    }

    func refreshState() async {
        guard let dyn = SCDynamicStoreCreate(nil, "Koala.proxy.read" as CFString, nil, nil) else {
            state = .error("Cannot create SCDynamicStore")
            return
        }
        guard let proxies = SCDynamicStoreCopyProxies(dyn) as? [CFString: Any] else {
            state = .off
            return
        }
        let httpEnabled = (proxies[kCFNetworkProxiesHTTPEnable] as? Int) == 1
        let httpsEnabled = (proxies[kCFNetworkProxiesHTTPSEnable] as? Int) == 1
        let host = (proxies[kCFNetworkProxiesHTTPProxy] as? String) ?? "?"
        let port = UInt16((proxies[kCFNetworkProxiesHTTPPort] as? Int) ?? 0)
        if httpEnabled || httpsEnabled {
            state = .on(host: host, port: port)
        } else {
            state = .off
        }
    }

    /// Legacy: returns the equivalent shell command (for "copy manual" fallback UI).
    func enableCommand(host: String = "127.0.0.1", port: UInt16) async -> String {
        return "scutil --proxy --set <interface> --enabled (use Koala's Enable button instead)"
    }
    func disableCommand() async -> String {
        return "scutil --proxy --set <interface> --disabled (use Koala's Restore button instead)"
    }

    // MARK: - Private

    private func mutateProxies(apply: (inout [CFString: CFTypeRef]) -> Void) throws {
        // Create AuthorizationRef (triggers native macOS auth sheet — Touch ID supported)
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw ProxyConfigError.authCreateFailed(status)
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        // Open authenticated SCPreferences for system network config
        guard let prefs = SCPreferencesCreateWithAuthorization(
            nil,
            "Koala" as CFString,
            nil,    // nil = default system preferences (/Library/Preferences/SystemConfiguration/preferences.plist)
            auth
        ) else {
            throw ProxyConfigError.scPrefsCreateFailed
        }

        // Locate the current NetworkSet (active location)
        guard let netSet = SCNetworkSetCopyCurrent(prefs) else {
            throw ProxyConfigError.networkSetMissing
        }

        // Enumerate services in the active set; modify proxies of each
        guard let services = SCNetworkSetCopyServices(netSet) as? [SCNetworkService], !services.isEmpty else {
            throw ProxyConfigError.noServices
        }

        var mutated = false
        for svc in services {
            guard SCNetworkServiceGetEnabled(svc) else { continue }
            guard let proto = SCNetworkServiceCopyProtocol(svc, kSCNetworkProtocolTypeProxies) else { continue }
            var current = (SCNetworkProtocolGetConfiguration(proto) as? [CFString: CFTypeRef]) ?? [:]
            apply(&current)
            if SCNetworkProtocolSetConfiguration(proto, current as CFDictionary) {
                mutated = true
            }
        }

        guard mutated else { throw ProxyConfigError.noServices }

        // Commit + Apply. CommitChanges may trigger the native auth dialog
        // (Touch ID or password) — same UX as Trust Settings dialog.
        guard SCPreferencesCommitChanges(prefs) else {
            let err = SCError()
            // -60005 / errAuthorizationCanceled etc. mapped via SCError
            if err == 1010 || err == -60006 || err == -60008 {
                throw ProxyConfigError.cancelled
            }
            throw ProxyConfigError.commitFailed(err)
        }
        guard SCPreferencesApplyChanges(prefs) else {
            throw ProxyConfigError.applyFailed(SCError())
        }
    }
}

enum ProxyConfigError: Error, LocalizedError {
    case noServices
    case cancelled
    case authCreateFailed(OSStatus)
    case scPrefsCreateFailed
    case networkSetMissing
    case commitFailed(Int32)
    case applyFailed(Int32)
    case subprocessFailed(String)

    var errorDescription: String? {
        switch self {
        case .noServices:                  return "No active network services found."
        case .cancelled:                   return "Cancelled."
        case .authCreateFailed(let s):     return "AuthorizationCreate failed (status \(s))."
        case .scPrefsCreateFailed:         return "Cannot open system network preferences."
        case .networkSetMissing:           return "No active network location."
        case .commitFailed(let s):         return "Commit failed (SCError \(s))."
        case .applyFailed(let s):          return "Apply failed (SCError \(s))."
        case .subprocessFailed(let m):     return m
        }
    }
}
