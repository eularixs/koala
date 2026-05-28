import XCTest
@testable import koala

// MARK: - MockShellExecutor

/// Deterministic shell executor for tests. No real subprocesses are spawned.
final class MockShellExecutor: ShellExecutor, @unchecked Sendable {

    var appleScriptResult: Result<String, Error> = .success("")
    var processResult: (Int32, String, String) = (0, "", "")

    func run(appleScript: String) throws -> String {
        switch appleScriptResult {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }

    func run(executable: String, arguments: [String]) async throws -> (Int32, String, String) {
        return processResult
    }
}

// MARK: - TrustInstallerTests

@MainActor
final class TrustInstallerTests: XCTestCase {

    func testRefreshStatus_returnsNotInstalled_whenCertAbsent() async {
        let mock = MockShellExecutor()
        mock.processResult = (44, "", "SecKeychainSearchCopyNext: The specified item could not be found.")
        let sut = TrustInstaller(shell: mock)

        await sut.refreshStatus()

        XCTAssertEqual(sut.status, .notInstalled)
    }

    func testRefreshStatus_returnsInstalled_whenCertPresent() async {
        let mock = MockShellExecutor()
        mock.processResult = (0, "attributes: ...", "")
        let sut = TrustInstaller(shell: mock)

        await sut.refreshStatus()

        XCTAssertEqual(sut.status, .installed)
    }

    func testInstall_throwsPemFileNotFound_whenFileAbsent() async {
        let mock = MockShellExecutor()
        let sut  = TrustInstaller(shell: mock)
        let missing = URL(fileURLWithPath: "/tmp/does_not_exist_koala_test_\(UUID().uuidString).pem")

        do {
            try await sut.install(pemFileURL: missing)
            XCTFail("Expected throw")
        } catch TrustInstaller.InstallError.pemFileNotFound(let url) {
            XCTAssertEqual(url, missing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstall_setsStatusInstalled_onSuccess() async throws {
        let tmp  = FileManager.default.temporaryDirectory
            .appendingPathComponent("KoalaTestCA_\(UUID().uuidString).pem")
        try "FAKE PEM".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mock = MockShellExecutor()
        mock.appleScriptResult = .success("")
        let sut = TrustInstaller(shell: mock)

        try await sut.install(pemFileURL: tmp)

        XCTAssertEqual(sut.status, .installed)
    }

    func testInstall_setsStatusError_onCancellation() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("KoalaTestCA_\(UUID().uuidString).pem")
        try "FAKE PEM".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mock = MockShellExecutor()
        mock.appleScriptResult = .failure(TrustInstaller.InstallError.cancelled)
        let sut = TrustInstaller(shell: mock)

        do {
            try await sut.install(pemFileURL: tmp)
            XCTFail("Expected throw")
        } catch TrustInstaller.InstallError.cancelled {
            // expected
        }

        XCTAssertEqual(sut.status, .error("Cancelled"))
    }

    func testUninstall_setsStatusNotInstalled_onSuccess() async throws {
        let mock = MockShellExecutor()
        mock.appleScriptResult = .success("")
        let sut = TrustInstaller(shell: mock)

        try await sut.uninstall()

        XCTAssertEqual(sut.status, .notInstalled)
    }

    func testInitialStatus_isUnknown() {
        let mock = MockShellExecutor()
        let sut  = TrustInstaller(shell: mock)
        XCTAssertEqual(sut.status, .unknown)
    }
}
