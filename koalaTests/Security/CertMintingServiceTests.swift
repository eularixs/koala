import XCTest
import X509
import Crypto
import SwiftASN1
@testable import koala

// MARK: - CertMintingServiceTests

final class CertMintingServiceTests: XCTestCase {

    // MARK: Setup helpers

    private func makeCA() async throws -> KoalaRootCA {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }
        return ca
    }

    private func makeSUT(ca: KoalaRootCA) async -> CertMintingService {
        await MainActor.run { CertMintingService(ca: ca) }
    }

    // MARK: SAN — simple host

    func testLeafCert_sanContainsHost() async throws {
        let ca  = try await makeCA()
        let sut = await makeSUT(ca: ca)
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let pair = try await MainActor.run { try sut.leafCertificate(for: "example.com") }

        let san = try pair.certificate.extensions.subjectAlternativeNames
        let dnsNames = san?.compactMap { name -> String? in
            if case .dnsName(let s) = name { return s }
            return nil
        } ?? []
        XCTAssertTrue(dnsNames.contains("example.com"), "SAN must include example.com, got \(dnsNames)")
    }

    // MARK: SAN — wildcard for 3-label host

    func testLeafCert_sanContainsWildcardForThreeLabelHost() async throws {
        let ca  = try await makeCA()
        let sut = await makeSUT(ca: ca)
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let host = "api.auth.eularix.com"
        let pair = try await MainActor.run { try sut.leafCertificate(for: host) }

        let san = try pair.certificate.extensions.subjectAlternativeNames
        let dnsNames = san?.compactMap { name -> String? in
            if case .dnsName(let s) = name { return s }
            return nil
        } ?? []

        XCTAssertTrue(dnsNames.contains(host), "SAN must contain \(host)")
        XCTAssertTrue(dnsNames.contains("*.auth.eularix.com"),
                      "SAN must contain wildcard *.auth.eularix.com, got \(dnsNames)")
    }

    // MARK: SAN — two-label host gets no wildcard

    func testLeafCert_noWildcardForTwoLabelHost() async throws {
        let ca  = try await makeCA()
        let sut = await makeSUT(ca: ca)
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let pair = try await MainActor.run { try sut.leafCertificate(for: "example.com") }

        let san = try pair.certificate.extensions.subjectAlternativeNames
        let dnsNames = san?.compactMap { name -> String? in
            if case .dnsName(let s) = name { return s }
            return nil
        } ?? []

        XCTAssertFalse(dnsNames.contains("*.com"), "Two-label host must not add wildcard")
        XCTAssertEqual(dnsNames, ["example.com"])
    }

    // MARK: Signed by CA

    func testLeafCert_isSignedByCA() async throws {
        let ca  = try await makeCA()
        let sut = await makeSUT(ca: ca)
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let caCert = await MainActor.run { ca.certificate! }
        let pair   = try await MainActor.run { try sut.leafCertificate(for: "example.com") }

        // Verify via RFC5280 chain validation (CA as trust root, no intermediates)
        var verifier = Verifier(rootCertificates: CertificateStore([caCert])) {
            RFC5280Policy(validationTime: Date())
        }
        let result = await verifier.validate(
            leaf: pair.certificate,
            intermediates: CertificateStore()
        )

        guard case .validCertificate = result else {
            return XCTFail("Chain validation failed: \(result)")
        }
    }

    // MARK: Cache hit

    func testLeafCert_cacheHitOnRepeatCall() async throws {
        let ca  = try await makeCA()
        let sut = await makeSUT(ca: ca)
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let pair1 = try await MainActor.run { try sut.leafCertificate(for: "example.com") }
        let pair2 = try await MainActor.run { try sut.leafCertificate(for: "example.com") }

        XCTAssertEqual(pair1.certificate, pair2.certificate, "Same cert should be returned from cache")
    }

    // MARK: Cache eviction after 200 entries

    func testCache_evictsOldestWhen200EntriesExceeded() async throws {
        let ca  = try await makeCA()
        let sut = await makeSUT(ca: ca)
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        // Mint 200 unique hosts
        for i in 0..<200 {
            _ = try await MainActor.run { try sut.leafCertificate(for: "host-\(i).example.com") }
        }

        // Record cert for host-0 (should still be in cache)
        let certForHost0Before = try await MainActor.run {
            try sut.leafCertificate(for: "host-0.example.com").certificate
        }

        // Mint one more to push over the limit — host-0 should be evicted
        _ = try await MainActor.run { try sut.leafCertificate(for: "host-200.example.com") }

        // host-0 is evicted; minting again produces a fresh cert (different key)
        let certForHost0After = try await MainActor.run {
            try sut.leafCertificate(for: "host-0.example.com").certificate
        }

        XCTAssertNotEqual(certForHost0Before, certForHost0After,
                          "After eviction a fresh cert should be minted for host-0")
    }
}

// MARK: - Extensions convenience

private extension Certificate.Extensions {
    var subjectAlternativeNames: SubjectAlternativeNames? {
        get throws {
            try self[oid: .X509ExtensionID.subjectAlternativeName].map { try SubjectAlternativeNames($0) }
        }
    }
}
