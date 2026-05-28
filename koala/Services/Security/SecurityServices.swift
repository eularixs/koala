import Foundation

// MARK: - SecurityServices
//
// Shared bootstrap for HTTPS interception services.
// Wire into environment at scene level (see StateContainer or koalaApp).
//
// Usage in views:
//   .environment(SecurityServices.koalaRootCA)
//   .environment(SecurityServices.trustInstaller)

@MainActor
enum SecurityServices {
    static let koalaRootCA = KoalaRootCA.shared
    static let trustInstaller = TrustInstaller()
    static let certMinter = CertMintingService(ca: koalaRootCA)
    static let systemProxy = SystemProxyManager()
}
