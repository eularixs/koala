import Foundation
import Observation

// MARK: - CACertificateManager (STUB)
//
// Future-iteration scaffolding for HTTPS interception. Not yet implemented —
// HTTPS recording is explicitly out of scope for the MVP recording proxy.
//
// Full flow when implemented:
//   1. Generate a self-signed root CA (RSA-2048 or P-256) using Security.framework
//      SecKeyCreateRandomKey + a CSR-equivalent constructed by hand.
//   2. Write `.cer` to disk and call SecCertificateAddToKeychain into the user
//      System keychain (requires admin auth via SFAuthorization).
//   3. Programmatically set the cert's trust settings (kSecTrustSettingsResult)
//      to "Always Trust" for SSL — this requires SecTrustSettingsSetTrustSettings
//      with admin domain → another auth prompt.
//   4. On each intercepted HTTPS connection (CONNECT host:443), the proxy
//      mints a leaf cert for `host` signed by the root CA, then performs a
//      TLS server handshake with the client using that cert; meanwhile it
//      opens an outbound TLS client connection to the real host. Bytes are
//      decrypted, recorded, and re-encrypted on each side.
//   5. On uninstall, remove the cert from the keychain and revert trust
//      settings.
//
// Reference impls to mimic: mitmproxy, Charles, Proxyman.
@MainActor
@Observable
final class CACertificateManager {

    private(set) var isInstalled: Bool = false
    private(set) var lastError: String?

    init() {}

    /// Stub. Returns placeholder bytes and logs a TODO.
    @discardableResult
    func generateRootCA() throws -> Data {
        print("TODO: implement CA generation (Security.framework SecKeyCreateRandomKey + X.509 building).")
        return Data("KOALA_PLACEHOLDER_CA".utf8)
    }

    /// Stub. Will eventually add cert to System keychain with admin auth.
    func installToKeychain() async throws {
        print("TODO: implement keychain install (SecCertificateAddToKeychain + SecTrustSettingsSetTrustSettings).")
        lastError = "HTTPS interception not yet supported in this version."
    }

    /// Stub. Reverts keychain trust + removes cert.
    func uninstall() throws {
        print("TODO: implement keychain uninstall.")
        isInstalled = false
    }
}
