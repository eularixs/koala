import Foundation
import Security
import X509
import Crypto
import SwiftASN1
import Observation

// MARK: - KoalaRootCA

/// Manages the Koala root CA lifecycle: generate, store in Keychain, export PEM.
@MainActor
@Observable
final class KoalaRootCA {

    static let shared = KoalaRootCA()

    // MARK: Keychain keys

    private static let certKeychainKey = "app.koala.rootCA.cert.v1"
    private static let keyKeychainKey  = "app.koala.rootCA.key.v1"

    // MARK: Observable state

    private(set) var certificate: Certificate?
    private(set) var privateKey: P256.Signing.PrivateKey?

    var isGenerated: Bool { certificate != nil && privateKey != nil }

    /// Sync trust check — evaluates system trust on the current cert.
    var isTrusted: Bool {
        guard let cert = certificate,
              let secCert = secCertificate(from: cert) else { return false }
        return evaluateTrust(for: secCert)
    }

    // MARK: Trust check

    /// Async variant; use this in non-blocking contexts.
    func isTrustedInSystem() async -> Bool { isTrusted }

    // MARK: Init

    init() {
        loadIfExists()
    }

    // MARK: Load

    /// Loads existing CA from Keychain; leaves state nil if none found.
    func loadIfExists() {
        do {
            guard let cert = try loadCertFromKeychain(),
                  let key  = try loadKeyFromKeychain() else { return }
            self.certificate = cert
            self.privateKey  = key
        } catch {
            // Silently ignore; caller checks isGenerated
        }
    }

    // MARK: Generate

    /// Generates a P-256 keypair + self-signed CA cert, saves to Keychain.
    func generate() throws {
        let key  = P256.Signing.PrivateKey()
        let name = try DistinguishedName {
            CommonName("Koala Root CA")
            OrganizationName("Koala")
        }
        let now    = Date()
        let expiry = Calendar.current.date(byAdding: .year, value: 10, to: now)!

        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: 0)
            )
            Critical(
                KeyUsage(keyCertSign: true, cRLSign: true)
            )
        }

        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: now,
            notValidAfter: expiry,
            issuer: name,
            subject: name,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(key)
        )

        self.certificate = cert
        self.privateKey  = key
        try saveToKeychain()
    }

    // MARK: PEM export

    /// PEM-encoded cert string.
    func certificatePEM() throws -> String {
        guard let cert = certificate else { throw CAError.notGenerated }
        let pemDoc = try cert.serializeAsPEM()
        return pemDoc.pemString
    }

    /// Writes cert PEM to a URL (called by UI file panel).
    func exportPEM(to url: URL) throws {
        let pem = try certificatePEM()
        try pem.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Keychain CRUD

    func saveToKeychain() throws {
        guard let cert = certificate, let key = privateKey else { throw CAError.notGenerated }
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        let certData = Data(serializer.serializedBytes)
        try KeychainService.shared.set(certData, for: Self.certKeychainKey)
        let keyData = key.rawRepresentation
        try KeychainService.shared.set(keyData, for: Self.keyKeychainKey)
    }

    /// Removes CA from Keychain and resets in-memory state.
    func deleteFromKeychain() throws {
        try KeychainService.shared.delete(Self.certKeychainKey)
        try KeychainService.shared.delete(Self.keyKeychainKey)
        certificate = nil
        privateKey  = nil
    }

    // MARK: Private helpers

    private func loadCertFromKeychain() throws -> Certificate? {
        guard let data = try KeychainService.shared.data(for: Self.certKeychainKey) else { return nil }
        return try Certificate(derEncoded: [UInt8](data))
    }

    private func loadKeyFromKeychain() throws -> P256.Signing.PrivateKey? {
        guard let data = try KeychainService.shared.data(for: Self.keyKeychainKey) else { return nil }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    private func secCertificate(from cert: Certificate) -> SecCertificate? {
        var serializer = DER.Serializer()
        guard (try? cert.serialize(into: &serializer)) != nil else { return nil }
        let data = Data(serializer.serializedBytes)
        return SecCertificateCreateWithData(nil, data as CFData)
    }

    private func evaluateTrust(for secCert: SecCertificate) -> Bool {
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        guard SecTrustCreateWithCertificates(secCert, policy, &trust) == errSecSuccess,
              let trust else { return false }
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }
}

// MARK: - CAError

enum CAError: Error, LocalizedError {
    case notGenerated
    case trustInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .notGenerated:               return "Koala root CA has not been generated yet."
        case .trustInstallFailed(let m):  return "Trust install failed: \(m)"
        }
    }
}
