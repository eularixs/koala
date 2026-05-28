import Foundation
import AppKit
import Observation

// MARK: - ShellExecutor

/// Abstracts shell command execution so tests can inject a mock.
protocol ShellExecutor: Sendable {
    /// Runs a command via NSAppleScript `do shell script`.
    /// - Returns: stdout text (may be empty).
    /// - Throws: `TrustInstaller.InstallError` on failure.
    func run(appleScript: String) throws -> String

    /// Runs a process and returns (exitCode, stdout, stderr).
    func run(executable: String, arguments: [String]) async throws -> (Int32, String, String)
}

// MARK: - DefaultShellExecutor

struct DefaultShellExecutor: ShellExecutor {

    func run(appleScript source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw TrustInstaller.InstallError.scriptFailed("Failed to create NSAppleScript")
        }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 || msg.contains("cancelled") || msg.contains("Cancelled") {
                throw TrustInstaller.InstallError.cancelled
            }
            // -60007 = wrong password (after 3 attempts user gives up)
            if code == -60007 || msg.contains("user name or password was incorrect") {
                throw TrustInstaller.InstallError.scriptFailed("Wrong admin password. Use your macOS login password (Touch ID won't work in this dialog).")
            }
            throw TrustInstaller.InstallError.scriptFailed(msg)
        }
        return result.stringValue ?? ""
    }

    func run(executable: String, arguments: [String]) async throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}

// MARK: - TrustInstaller

/// Installs / uninstalls Koala Root CA in the macOS System Keychain.
///
/// Auth strategy: NSAppleScript `do shell script "..." with administrator privileges`.
/// Rationale: `AuthorizationExecuteWithPrivileges` is deprecated in macOS 12 and
/// emits deprecation warnings under Swift 6 strict concurrency. NSAppleScript with
/// administrator privileges shows the same native macOS auth dialog, requires no
/// extra entitlements, and is explicitly permitted when user-initiated. The
/// approach matches what Proxyman and other sandboxed MITM tools use.
///
/// Sandbox note: NSAppleScript is restricted in sandboxed apps for outbound
/// scripting of other apps, but `do shell script` targeting the shell itself
/// (not another app) is allowed when the user explicitly triggers it and the
/// administrator dialog provides consent.
@MainActor
@Observable
final class TrustInstaller {

    // MARK: Status

    enum Status: Equatable {
        case unknown
        case notInstalled
        case installed
        case error(String)
    }

    // MARK: Errors

    enum InstallError: Error, LocalizedError {
        case pemFileNotFound(URL)
        case cancelled
        case scriptFailed(String)
        case subprocessFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .pemFileNotFound(let url): return "PEM file not found at \(url.path)"
            case .cancelled:               return "User cancelled the admin authorisation dialog."
            case .scriptFailed(let msg):   return "AppleScript error: \(msg)"
            case .subprocessFailed(let code, let stderr):
                return "security exited \(code): \(stderr)"
            }
        }
    }

    // MARK: Constants

    private static let certName       = "Koala Root CA"
    private static let systemKeychain = "/Library/Keychains/System.keychain"
    /// User login keychain — no admin password required for install.
    /// Trusted by Safari, Chrome (via keychain), curl, and most macOS apps.
    private static var loginKeychain: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Keychains/login.keychain-db"
    }

    // MARK: State

    private(set) var status: Status = .unknown

    // MARK: Dependencies

    private let shell: ShellExecutor

    init(shell: ShellExecutor = DefaultShellExecutor()) {
        self.shell = shell
    }

    // MARK: Public API

    /// Installs `pemFileURL` as a trusted root in the user's login Keychain.
    /// No admin password required. Trusted by Safari, Chrome, curl, etc.
    /// Sets `status` to `.installed` on success.
    func install(pemFileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: pemFileURL.path) else {
            throw InstallError.pemFileNotFound(pemFileURL)
        }

        // Read PEM and convert to SecCertificate
        let pemString = try String(contentsOf: pemFileURL, encoding: .utf8)
        let derData = try Self.derFromPEM(pemString)
        guard let secCert = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw InstallError.scriptFailed("Failed to parse PEM certificate")
        }

        // 1. Add cert to login keychain (idempotent — ignores duplicate)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecAttrLabel as String: Self.certName,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            throw InstallError.subprocessFailed(addStatus, "SecItemAdd failed: \(addStatus)")
        }

        // 2. Set trust settings — explicitly trust as root for SSL.
        //    macOS shows native Touch ID / password dialog automatically.
        var sslPolicy: SecPolicy? = SecPolicyCreateSSL(true, nil)
        let trustEntry: [String: Any] = [
            kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue),
            kSecTrustSettingsPolicy as String: sslPolicy as Any,
        ]
        let trustStatus = SecTrustSettingsSetTrustSettings(
            secCert,
            .user,                          // user domain (no sudo needed)
            [trustEntry] as CFArray
        )
        sslPolicy = nil
        switch trustStatus {
        case errSecSuccess:
            status = .installed
        case errSecUserCanceled, errAuthorizationCanceled:
            throw InstallError.cancelled
        default:
            status = .error("Trust install failed (status \(trustStatus))")
            throw InstallError.subprocessFailed(trustStatus, "SecTrustSettingsSetTrustSettings failed: \(trustStatus)")
        }
    }

    /// Strips PEM header/footer + base64-decodes to DER bytes.
    private static func derFromPEM(_ pem: String) throws -> Data {
        let lines = pem.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let body = lines.filter {
            !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END")
        }.joined()
        guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else {
            throw InstallError.scriptFailed("PEM base64 decode failed")
        }
        return data
    }

    /// Installs system-wide via admin password (broader trust, e.g. system services).
    /// Use this only if user-keychain install isn't sufficient (rare).
    func installSystemWide(pemFileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: pemFileURL.path) else {
            throw InstallError.pemFileNotFound(pemFileURL)
        }
        let path = pemFileURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let cmd  = "/usr/bin/security add-trusted-cert -d -r trustRoot -k '\(Self.systemKeychain)' '\(path)'"
        let src  = "do shell script \"\(cmd)\" with prompt \"Koala wants to install its root certificate system-wide.\" with administrator privileges"
        do {
            try shell.run(appleScript: src)
            status = .installed
        } catch InstallError.cancelled {
            status = .error("Cancelled")
            throw InstallError.cancelled
        } catch let err as InstallError {
            status = .error(err.localizedDescription ?? "Unknown error")
            throw err
        }
    }

    /// Removes Koala Root CA from the user's login Keychain.
    /// No admin password required.
    func uninstall() async throws {
        let (code, _, stderr) = try await shell.run(
            executable: "/usr/bin/security",
            arguments: [
                "delete-certificate",
                "-c", Self.certName,
                Self.loginKeychain,
            ]
        )
        if code == 0 {
            status = .notInstalled
        } else {
            let msg = stderr.isEmpty ? "Uninstall failed (exit \(code))" : stderr
            status = .error(msg)
            throw InstallError.subprocessFailed(code, msg)
        }
    }

    /// Checks login Keychain (then System) for "Koala Root CA" and updates `status`.
    func refreshStatus() async {
        do {
            let (loginCode, _, _) = try await shell.run(
                executable: "/usr/bin/security",
                arguments: ["find-certificate", "-c", Self.certName, Self.loginKeychain]
            )
            if loginCode == 0 {
                status = .installed
                return
            }
            let (sysCode, _, _) = try await shell.run(
                executable: "/usr/bin/security",
                arguments: ["find-certificate", "-c", Self.certName, Self.systemKeychain]
            )
            status = (sysCode == 0) ? .installed : .notInstalled
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}
