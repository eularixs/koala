import Foundation
import Security

// Apple marked AuthorizationExecuteWithPrivileges as "unavailable in Swift" via
// the Security framework's modulemap. The underlying C symbol still ships in
// libSystem on macOS 14/15/26+. Re-declare via @_silgen_name to bypass the
// Swift importer's unavailability annotation.
@_silgen_name("AuthorizationExecuteWithPrivileges")
private func _AuthorizationExecuteWithPrivileges(
    _ authorization: AuthorizationRef,
    _ pathToTool: UnsafePointer<CChar>,
    _ options: AuthorizationFlags,
    _ arguments: UnsafePointer<UnsafeMutablePointer<CChar>?>,
    _ communicationsPipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
) -> OSStatus

// MARK: - AdminAuth
//
// Runs a privileged shell command via Apple's AuthorizationServices.
// Triggers the native macOS auth sheet — supports Touch ID on Apple Silicon
// Macs running macOS 14+, falls back to typed password otherwise.
//
// Uses `AuthorizationExecuteWithPrivileges` which is deprecated since 10.7
// but still functional in macOS 26 / Sequoia (2026). Apple's modern
// replacement (SMAppService) requires Developer ID signing — Koala is
// ad-hoc unsigned for Homebrew distribution, so this is the best option.

enum AdminAuthError: LocalizedError {
    case createAuthFailed(OSStatus)
    case cancelled
    case copyRightsFailed(OSStatus)
    case executeFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .createAuthFailed(let s): return "AuthorizationCreate failed (status \(s))"
        case .cancelled:               return "Cancelled by user"
        case .copyRightsFailed(let s): return "Authentication failed (status \(s))"
        case .executeFailed(let s):    return "Privileged execute failed (status \(s))"
        }
    }
}

enum AdminAuth {

    /// Runs `executable` with `arguments` as root, after presenting macOS native
    /// auth sheet to the user. Sheet supports Touch ID on Apple Silicon when
    /// the user has it enabled.
    ///
    /// - Throws: `AdminAuthError`
    /// - Parameter prompt: Optional human-readable description shown in the auth sheet.
    static func run(
        executable: String,
        arguments: [String],
        prompt: String? = nil
    ) throws {
        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw AdminAuthError.createAuthFailed(status)
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        // Request system.privilege.admin right with interactive UI allowed
        try "system.privilege.admin".withCString { rightCStr in
            var rightItem = AuthorizationItem(
                name: rightCStr,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            try withUnsafeMutablePointer(to: &rightItem) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)

                // Optional prompt for the auth sheet
                if let prompt {
                    try prompt.withCString { promptCStr in
                        var envItem = AuthorizationItem(
                            name: kAuthorizationEnvironmentPrompt,
                            valueLength: strlen(promptCStr),
                            value: UnsafeMutableRawPointer(mutating: promptCStr),
                            flags: 0
                        )
                        try withUnsafeMutablePointer(to: &envItem) { envPtr in
                            var env = AuthorizationEnvironment(count: 1, items: envPtr)
                            status = AuthorizationCopyRights(
                                auth, &rights, &env,
                                [.interactionAllowed, .preAuthorize, .extendRights],
                                nil
                            )
                            try checkAuth(status)
                        }
                    }
                } else {
                    status = AuthorizationCopyRights(
                        auth, &rights, nil,
                        [.interactionAllowed, .preAuthorize, .extendRights],
                        nil
                    )
                    try checkAuth(status)
                }
            }
        }

        // Execute with privileges. The C signature wants a NULL-terminated argv
        // (char * const *). Swift's import gives non-optional pointer type so
        // we allocate manually + rebind.
        let argc = arguments.count
        let argvBuf = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: argc + 1)
        for (i, arg) in arguments.enumerated() {
            argvBuf[i] = strdup(arg)
        }
        argvBuf[argc] = nil
        defer {
            for i in 0..<argc { free(argvBuf[i]) }
            argvBuf.deallocate()
        }
        status = _AuthorizationExecuteWithPrivileges(
            auth,
            executable,
            [],
            argvBuf,
            nil
        )
        guard status == errAuthorizationSuccess else {
            throw AdminAuthError.executeFailed(status)
        }
    }

    private static func checkAuth(_ status: OSStatus) throws {
        if status == errAuthorizationCanceled {
            throw AdminAuthError.cancelled
        }
        guard status == errAuthorizationSuccess else {
            throw AdminAuthError.copyRightsFailed(status)
        }
    }
}
