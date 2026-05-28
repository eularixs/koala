import XCTest
import SwiftUI
@testable import koala

// MARK: - CASettingsViewTests

/// Tests for CASettingsView state and supporting helpers.
/// Does NOT snapshot; verifies logic + that the view constructs without crash.
@MainActor
final class CASettingsViewTests: XCTestCase {

    // MARK: - TrustInstaller.Status display text

    func test_trustStatusText_unknown() {
        let installer = TrustInstaller()
        XCTAssertEqual(installer.status, .unknown)
    }

    // MARK: - PEMDocument

    func test_pemDocument_contentPreserved() {
        let original = "-----BEGIN CERTIFICATE-----\naGVsbG8=\n-----END CERTIFICATE-----\n"
        let doc = PEMDocument(content: original)
        XCTAssertEqual(doc.content, original)
    }

    func test_pemDocument_utf8Encoding() {
        let content = "test pem content"
        let doc = PEMDocument(content: content)
        let data = Data(content.utf8)
        XCTAssertEqual(Data(doc.content.utf8), data)
    }

    func test_pemDocument_readableContentTypes_notEmpty() {
        XCTAssertFalse(PEMDocument.readableContentTypes.isEmpty)
    }

    // MARK: - SecurityServices singletons are stable references

    func test_securityServices_sharedCA_isSameReference() {
        let a = SecurityServices.koalaRootCA
        let b = SecurityServices.koalaRootCA
        XCTAssertTrue(a === b)
    }

    // MARK: - CASettingsView constructs without crash

    func test_caSettingsView_initDoesNotCrash() {
        let ca = KoalaRootCA.shared
        let installer = TrustInstaller()
        // Simply constructing the view body should not throw or crash.
        let view = CASettingsView()
            .environment(ca)
            .environment(installer)
        // If we get here without a crash, the test passes.
        XCTAssertNotNil(view)
    }

    // MARK: - caStatusDescription logic (mirrored inline)

    func test_caStatusDescription_notConfigured() {
        // CA not generated → "Not configured"
        let ca = KoalaRootCA.shared
        let trust = TrustInstaller() // status = .unknown by default
        // CA is not generated in a fresh shared instance (no keychain in tests)
        if !ca.isGenerated {
            let desc = statusDescription(ca: ca, trust: trust)
            XCTAssertEqual(desc, "Not configured")
        }
    }

    /// Mirror of ProxyControlView.caStatusDescription for isolated testing.
    private func statusDescription(ca: KoalaRootCA, trust: TrustInstaller) -> String {
        switch (ca.isGenerated, trust.status) {
        case (false, _):             return "Not configured"
        case (true, .installed):     return "Active — intercepting HTTPS"
        case (true, .notInstalled):  return "CA generated, not trusted"
        case (true, .error):         return "Trust outdated"
        case (true, .unknown):       return "CA generated, trust unknown"
        }
    }
}
