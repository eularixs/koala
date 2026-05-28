import XCTest
import X509
import Crypto
import SwiftASN1
@testable import koala

// MARK: - KoalaRootCATests

final class KoalaRootCATests: XCTestCase {

    // MARK: generate

    func testGenerate_setsStateAndIsGenerated() async throws {
        let ca = await MainActor.run { KoalaRootCA() }

        try await MainActor.run { try ca.generate() }

        let isGenerated = await MainActor.run { ca.isGenerated }
        XCTAssertTrue(isGenerated)
        let cert = await MainActor.run { ca.certificate }
        let key  = await MainActor.run { ca.privateKey }
        XCTAssertNotNil(cert)
        XCTAssertNotNil(key)
    }

    // MARK: certificatePEM

    func testCertificatePEM_returnsValidPEMString() async throws {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }

        let pem = try await MainActor.run { try ca.certificatePEM() }

        XCTAssertTrue(pem.hasPrefix("-----BEGIN CERTIFICATE-----"), "PEM must start with BEGIN marker")
        XCTAssertTrue(pem.contains("-----END CERTIFICATE-----"), "PEM must contain END marker")
    }

    // MARK: Validity period

    func testGeneratedCert_hasApproxTenYearValidity() async throws {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }

        let cert = await MainActor.run { ca.certificate! }
        let intervalDays = cert.notValidAfter.timeIntervalSince(cert.notValidBefore) / 86400
        // 10 years ~3650 days; allow ±5 day for leap-year variation
        XCTAssertGreaterThan(intervalDays, 3645)
        XCTAssertLessThan(intervalDays, 3656)
    }

    // MARK: BasicConstraints isCA

    func testGeneratedCert_hasIsCATrue() async throws {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }

        let cert = await MainActor.run { ca.certificate! }
        let bc = try cert.extensions.basicConstraints
        guard case .isCertificateAuthority = bc else {
            return XCTFail("Expected isCertificateAuthority, got \(String(describing: bc))")
        }
    }

    // MARK: deleteFromKeychain clears state

    func testDeleteFromKeychain_clearsState() async throws {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }

        try await MainActor.run { try ca.deleteFromKeychain() }

        let isGenerated = await MainActor.run { ca.isGenerated }
        XCTAssertFalse(isGenerated)
        let cert = await MainActor.run { ca.certificate }
        XCTAssertNil(cert)
    }

    // MARK: loadIfExists after generate

    func testLoadIfExists_restoresCertAndKey() async throws {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }

        let certBefore = await MainActor.run { ca.certificate! }

        // New instance loads from Keychain
        let ca2 = await MainActor.run { KoalaRootCA() }
        await MainActor.run { ca2.loadIfExists() }

        let certAfter  = await MainActor.run { ca2.certificate }
        let isGenerated = await MainActor.run { ca2.isGenerated }

        XCTAssertTrue(isGenerated)
        XCTAssertEqual(certAfter, certBefore)

        // Cleanup
        try await MainActor.run { try ca2.deleteFromKeychain() }
    }
}
