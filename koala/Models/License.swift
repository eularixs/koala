import Foundation

// MARK: - LicenseTier

enum LicenseTier: String, Codable {
    case free
    case pro
    case lifetime
}

// MARK: - LicenseReceipt

/// The payload that gets signed by the activation server.
///
/// Re-encoded client-side as canonical JSON (sorted keys, ISO-8601 dates)
/// to verify the server signature.
struct LicenseReceipt: Codable, Equatable {
    let licenseId: String
    let tier: LicenseTier
    let deviceHash: String
    let activatedAt: Date
    /// 90 days after activation; revalidate against server after this passes.
    let validUntil: Date
    let userEmail: String?
}

// MARK: - SignedLicenseReceipt

/// Signed envelope returned by the activation API.
///
/// `signatureBase64` is `RSA-SHA256(canonical-JSON(receipt))` produced by
/// the server's private key; verified by clients against the bundled
/// `license-public-key.pem`.
struct SignedLicenseReceipt: Codable {
    let receipt: LicenseReceipt
    let signatureBase64: String
}
