import XCTest
import Darwin
import NIO
import NIOHTTP1
import NIOSSL
@testable import koala

// MARK: - NIOProxyHandshakeTests
//
// Verifies the NIO proxy lifecycle and MITM cert-minting round-trip.
// Full browser-to-upstream TLS tunnel is an integration concern; here we test:
//   1. NIOSSLContext can be built from a freshly minted leaf cert.
//   2. Proxy starts, listens, stops cleanly.
//   3. Proxy responds 200 to a raw CONNECT request.

final class NIOProxyHandshakeTests: XCTestCase {

    // MARK: Helpers

    private func makeCA() async throws -> KoalaRootCA {
        let ca = await MainActor.run { KoalaRootCA() }
        try await MainActor.run { try ca.generate() }
        return ca
    }

    // MARK: CertMinter -> NIOSSLContext round-trip

    func testNIOSSLContextBuiltFromMintedLeaf() async throws {
        let ca  = try await makeCA()
        let sut = await MainActor.run { CertMintingService(ca: ca) }
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let ctx = try await MainActor.run { try sut.niosslContext(for: "api.example.com") }
        XCTAssertNotNil(ctx)
    }

    func testNIOSSLContextDifferentHosts() async throws {
        let ca  = try await makeCA()
        let sut = await MainActor.run { CertMintingService(ca: ca) }
        defer { Task { try? await MainActor.run { try ca.deleteFromKeychain() } } }

        let ctx1 = try await MainActor.run { try sut.niosslContext(for: "api.example.com") }
        let ctx2 = try await MainActor.run { try sut.niosslContext(for: "auth.example.com") }

        XCTAssertNotNil(ctx1)
        XCTAssertNotNil(ctx2)
    }

    func testNIOSSLContextThrowsWhenNoCA() async throws {
        let emptyCA = await MainActor.run { KoalaRootCA() }
        let sut = await MainActor.run { CertMintingService(ca: emptyCA) }

        do {
            _ = try await MainActor.run { try sut.niosslContext(for: "example.com") }
            XCTFail("Expected CAError.notGenerated")
        } catch CAError.notGenerated {
            // expected
        }
    }

    // MARK: Proxy lifecycle

    func testProxyStartStop() async throws {
        let svc  = await MainActor.run { RecordingProxyService() }
        let port = try findFreePort()

        try await MainActor.run { try svc.start(port: port) }
        let state = await MainActor.run { svc.state }
        XCTAssertEqual(state, .listening(port: port))

        await MainActor.run { svc.stop() }
        let stopped = await MainActor.run { svc.state }
        XCTAssertEqual(stopped, .stopped)
    }

    func testProxyRestartSamePort() async throws {
        let svc  = await MainActor.run { RecordingProxyService() }
        let port = try findFreePort()

        try await MainActor.run { try svc.start(port: port) }
        try await MainActor.run { try svc.start(port: port) }

        let state = await MainActor.run { svc.state }
        XCTAssertEqual(state, .listening(port: port))
        await MainActor.run { svc.stop() }
    }

    // MARK: CONNECT responds 200

    func testProxyResponds200ToCONNECT() async throws {
        let svc = await MainActor.run {
            let s = RecordingProxyService()
            s.mode = .forward
            return s
        }
        let port = try findFreePort()
        try await MainActor.run { try svc.start(port: port) }
        defer { Task { await MainActor.run { svc.stop() } } }

        try await Task.sleep(nanoseconds: 150_000_000) // 150ms

        let conn = try SimpleTCPConn(host: "127.0.0.1", port: port)
        defer { conn.closeSocket() }

        conn.sendString("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")
        let response = conn.readAvailable(timeoutSeconds: 2)
        XCTAssertTrue(response.contains("200"), "Expected 200, got: \(response)")
    }

    // MARK: Free port helper

    private func findFreePort() throws -> UInt16 {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw NSError(domain: "sock", code: Int(errno)) }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = 0
        addr.sin_addr   = in_addr(s_addr: INADDR_ANY)

        withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = Darwin.getsockname(sock, sa, &len)
            }
        }

        return UInt16(bigEndian: addr.sin_port)
    }
}

// MARK: - SimpleTCPConn

private final class SimpleTCPConn {
    private let fd: Int32

    init(host: String, port: UInt16) throws {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw NSError(domain: "tcp", code: Int(errno)) }
        fd = sock
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        Darwin.inet_pton(AF_INET, host, &addr.sin_addr)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else {
            Darwin.close(sock)
            throw NSError(domain: "tcp-connect", code: Int(errno))
        }
    }

    func sendString(_ s: String) {
        let bytes = Array(s.utf8)
        _ = Darwin.send(fd, bytes, bytes.count, 0)
    }

    func readAvailable(timeoutSeconds: TimeInterval) -> String {
        var tv = timeval(tv_sec: Int(timeoutSeconds), tv_usec: 0)
        Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return "" }
        return String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
    }

    func closeSocket() { Darwin.close(fd) }
    deinit { Darwin.close(fd) }
}
