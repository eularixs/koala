import Foundation
import Security
import CryptoKit
import IOKit
import AppKit
import Observation

// MARK: - LicenseError

enum LicenseError: Error, LocalizedError {
    case invalidKey
    case network(String)
    case server(statusCode: Int, message: String)
    case decoding(Error)
    case signatureInvalid
    case publicKeyMissing
    case publicKeyMalformed(String)
    case notActivated

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "License key looks invalid."
        case .network(let msg): return "Network error: \(msg)"
        case .server(let code, let msg): return "Activation server error \(code): \(msg)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .signatureInvalid: return "License signature could not be verified."
        case .publicKeyMissing: return "Bundled license public key not found."
        case .publicKeyMalformed(let msg): return "License public key malformed: \(msg)"
        case .notActivated: return "No active license."
        }
    }
}

// MARK: - LicenseService

/// Manages client-side license activation, persistence, and signature
/// verification against a bundled RSA public key.
///
/// Storage: signed receipt JSON in Keychain (`license.receipt`).
/// Network: activation/validate/deactivate via `koala.app` endpoints
/// (placeholders until server ships).
@MainActor
@Observable
final class LicenseService {

    // MARK: State

    private(set) var activeReceipt: LicenseReceipt?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    var tier: LicenseTier { activeReceipt?.tier ?? .free }
    var isPro: Bool { tier != .free }
    var isLifetime: Bool { tier == .lifetime }

    // MARK: Config

    /// Placeholder endpoints — real server TBD.
    private let activationURL = "https://koala.app/api/activate"
    private let deactivationURL = "https://koala.app/api/deactivate"
    private let validationURL = "https://koala.app/api/validate"

    private let keychain = KeychainService.shared
    private let keychainKey = "license.receipt"
    private let deviceUUIDFallbackKey = "Koala.LicenseService.DeviceUUIDFallback"

    /// Grace period after `validUntil` during which the receipt still counts
    /// as valid offline (handles users who go offline for weeks).
    private let offlineGracePeriod: TimeInterval = 60 * 60 * 24 * 30

    // MARK: Init

    init() {
        loadFromKeychain()
    }

    // MARK: - Activation

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseError.invalidKey }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let payload: [String: String] = [
            "key": trimmed,
            "deviceHash": deviceHash(),
            "machineName": Host.current().localizedName ?? "Unknown Mac",
        ]

        let signed = try await postSignedReceipt(url: activationURL, body: payload)

        guard verifySignature(signed.receipt, signature: signed.signatureBase64) else {
            throw LicenseError.signatureInvalid
        }

        try persist(signed)
        activeReceipt = signed.receipt
    }

    // MARK: - Deactivation

    func deactivate() async throws {
        guard let receipt = activeReceipt else { throw LicenseError.notActivated }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let payload: [String: String] = [
            "licenseId": receipt.licenseId,
            "deviceHash": deviceHash(),
        ]

        // Best-effort server notification. We always clear local state, even
        // if the server can't be reached (user may be offline).
        do {
            _ = try await postJSON(url: deactivationURL, body: payload)
        } catch {
            lastError = error.localizedDescription
        }

        try? keychain.delete(keychainKey)
        activeReceipt = nil
    }

    // MARK: - Validation / Re-validation

    /// Called on launch / whenever we suspect the receipt may need a refresh.
    /// Silently fails offline (within grace period).
    func revalidateIfNeeded() async {
        guard let receipt = activeReceipt else { return }

        let now = Date()
        // Only hit the network if the receipt has actually expired.
        guard receipt.validUntil < now else { return }

        // Past grace period → wipe local state, force re-activation.
        let pastGrace = now.timeIntervalSince(receipt.validUntil) > offlineGracePeriod

        do {
            let payload: [String: String] = [
                "licenseId": receipt.licenseId,
                "deviceHash": deviceHash(),
            ]
            let signed = try await postSignedReceipt(url: validationURL, body: payload)
            guard verifySignature(signed.receipt, signature: signed.signatureBase64) else {
                if pastGrace { try? keychain.delete(keychainKey); activeReceipt = nil }
                return
            }
            try? persist(signed)
            activeReceipt = signed.receipt
        } catch {
            // Offline / server down. Tolerate within grace period.
            if pastGrace {
                try? keychain.delete(keychainKey)
                activeReceipt = nil
                lastError = "License expired and could not be revalidated."
            }
        }
    }

    // MARK: - Keychain

    func loadFromKeychain() {
        guard let data = (try? keychain.data(for: keychainKey)) ?? nil else {
            return
        }
        guard let signed = try? JSONDecoder.licenseDecoder.decode(SignedLicenseReceipt.self, from: data) else {
            try? keychain.delete(keychainKey)
            return
        }
        guard verifySignature(signed.receipt, signature: signed.signatureBase64) else {
            try? keychain.delete(keychainKey)
            return
        }
        // Verify deviceHash binding so a stolen receipt JSON can't be moved
        // to another Mac.
        guard signed.receipt.deviceHash == deviceHash() else {
            try? keychain.delete(keychainKey)
            return
        }
        // Past grace period → wipe (revalidateIfNeeded handles refresh).
        let pastGrace = Date().timeIntervalSince(signed.receipt.validUntil) > offlineGracePeriod
        if pastGrace {
            try? keychain.delete(keychainKey)
            return
        }
        activeReceipt = signed.receipt
    }

    private func persist(_ signed: SignedLicenseReceipt) throws {
        let data = try JSONEncoder.licenseEncoder.encode(signed)
        try keychain.set(data, for: keychainKey)
    }

    // MARK: - Networking

    private func postSignedReceipt(url: String, body: [String: String]) async throws -> SignedLicenseReceipt {
        let data = try await postJSON(url: url, body: body)
        do {
            return try JSONDecoder.licenseDecoder.decode(SignedLicenseReceipt.self, from: data)
        } catch {
            throw LicenseError.decoding(error)
        }
    }

    private func postJSON(url: String, body: [String: String]) async throws -> Data {
        guard let u = URL(string: url) else { throw LicenseError.network("Invalid URL: \(url)") }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown"
                throw LicenseError.server(statusCode: http.statusCode, message: msg)
            }
            return data
        } catch let err as LicenseError {
            throw err
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }
    }

    // MARK: - Device Hash

    /// SHA256(IOPlatformUUID + Host.localizedName). Falls back to a cached
    /// UUID in UserDefaults if the hardware UUID is inaccessible (sandbox).
    private func deviceHash() -> String {
        let hardwareID = hardwarePlatformUUID() ?? fallbackDeviceUUID()
        let machineName = Host.current().localizedName ?? ""
        let combined = hardwareID + machineName
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func hardwarePlatformUUID() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        let key = "IOPlatformUUID" as CFString
        guard let cfProp = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (cfProp.takeRetainedValue() as? String)
    }

    private func fallbackDeviceUUID() -> String {
        if let cached = UserDefaults.standard.string(forKey: deviceUUIDFallbackKey) {
            return cached
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceUUIDFallbackKey)
        return new
    }

    // MARK: - Signature Verification

    /// Verifies `signature` matches `RSA-SHA256(canonical-JSON(receipt))`
    /// using the bundled RSA public key.
    private func verifySignature(_ receipt: LicenseReceipt, signature: String) -> Bool {
        guard let signatureData = Data(base64Encoded: signature) else { return false }
        guard let canonical = try? JSONEncoder.licenseEncoder.encode(receipt) else { return false }

        do {
            let publicKey = try loadPublicKey()
            var error: Unmanaged<CFError>?
            let ok = SecKeyVerifySignature(
                publicKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                canonical as CFData,
                signatureData as CFData,
                &error
            )
            return ok
        } catch {
            return false
        }
    }

    private func loadPublicKey() throws -> SecKey {
        guard let url = Bundle.main.url(forResource: "license-public-key", withExtension: "pem"),
              let pem = try? String(contentsOf: url, encoding: .utf8) else {
            throw LicenseError.publicKeyMissing
        }

        // Strip PEM header/footer + comments + whitespace; decode base64 body.
        let base64 = pem
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("-----") }
            .joined()

        guard let derSPKI = Data(base64Encoded: base64) else {
            throw LicenseError.publicKeyMalformed("Base64 decode failed")
        }

        // PEM "PUBLIC KEY" is SubjectPublicKeyInfo (SPKI) — Security
        // framework wants the raw RSA modulus+exponent, so strip the
        // 24-byte ASN.1 header for an RSA-2048 SPKI.
        let rawRSAKey = stripSPKIHeader(derSPKI)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(rawRSAKey as CFData, attributes as CFDictionary, &error) else {
            let msg = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "Unknown"
            throw LicenseError.publicKeyMalformed(msg)
        }
        return key
    }

    /// Strips the SPKI ASN.1 prefix from a DER-encoded RSA 2048 public key.
    /// The SPKI envelope is 24 bytes for RSA-2048; if shorter we return the
    /// original (likely already raw PKCS#1).
    private func stripSPKIHeader(_ data: Data) -> Data {
        let spkiHeaderLength = 24
        // Quick sanity: SPKI starts with 0x30, raw PKCS#1 also starts with 0x30
        // — distinguish by length. RSA-2048 PKCS#1 is ~270 bytes, SPKI ~294.
        guard data.count > spkiHeaderLength + 250 else { return data }
        return data.subdata(in: spkiHeaderLength..<data.count)
    }
}

// MARK: - JSONEncoder/Decoder (canonical for signing)

private extension JSONEncoder {
    /// Sorted keys + ISO-8601 dates so the canonical JSON the server signs
    /// matches what we re-encode here for verification.
    static var licenseEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var licenseDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

