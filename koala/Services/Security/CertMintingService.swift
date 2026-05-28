import Foundation
import X509
import Crypto
import SwiftASN1
import NIOSSL

// MARK: - CertMintingService

/// Mints per-host leaf TLS certificates signed by KoalaRootCA, with an LRU cache.
/// NIO wiring (NIOSSLContext) is handled by the separate NIO proxy agent.
@MainActor
final class CertMintingService {

    private let ca: KoalaRootCA
    private var cache: [(host: String, cert: Certificate, key: P256.Signing.PrivateKey)] = []
    private let cacheMaxSize = 200

    init(ca: KoalaRootCA) { self.ca = ca }

    // MARK: Public API

    /// Returns (certificate, privateKey) for the given host. Cache hit on repeat calls.
    func leafCertificate(for host: String) throws -> (certificate: Certificate, key: P256.Signing.PrivateKey) {
        if let cached = cache.first(where: { $0.host == host }) {
            return (cached.cert, cached.key)
        }
        let pair = try mintLeaf(for: host)
        evictIfNeeded()
        cache.append((host: host, cert: pair.certificate, key: pair.key))
        return pair
    }

    /// Returns (certPEM, keyPEM) strings for the given host.
    func pemPair(for host: String) throws -> (certPEM: String, keyPEM: String) {
        let pair = try leafCertificate(for: host)
        let certPEM = try pair.certificate.serializeAsPEM().pemString
        let keyPEM  = try Certificate.PrivateKey(pair.key).serializeAsPEM().pemString
        return (certPEM, keyPEM)
    }

    func clearCache() { cache.removeAll() }

    // MARK: Private

    private func mintLeaf(for host: String) throws -> (certificate: Certificate, key: P256.Signing.PrivateKey) {
        guard let caCert = ca.certificate, let caKey = ca.privateKey else {
            throw CAError.notGenerated
        }
        let leafKey = P256.Signing.PrivateKey()
        let now     = Date()
        let expiry  = now.addingTimeInterval(397 * 24 * 3600)   // 397-day Apple max

        let san = buildSAN(for: host)
        let eku = try ExtendedKeyUsage([.serverAuth])
        let extensions = try Certificate.Extensions {
            SubjectAlternativeNames(san)
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(
                KeyUsage(digitalSignature: true, keyEncipherment: true)
            )
            eku
        }

        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(leafKey.publicKey),
            notValidBefore: now,
            notValidAfter: expiry,
            issuer: caCert.subject,
            subject: try DistinguishedName { CommonName(host) },
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(caKey)
        )
        return (cert, leafKey)
    }

    /// Builds SAN entries for a host. Adds wildcard for 3+ label hosts.
    private func buildSAN(for host: String) -> [GeneralName] {
        var names: [GeneralName] = [.dnsName(host)]
        let labels = host.split(separator: ".").map(String.init)
        if labels.count >= 3 {
            let wildcard = "*." + labels.dropFirst().joined(separator: ".")
            names.append(.dnsName(wildcard))
        }
        return names
    }

    private func evictIfNeeded() {
        if cache.count >= cacheMaxSize {
            cache.removeFirst()
        }
    }
}

// MARK: - NIOSSL bridge

extension CertMintingService {
    /// Builds a NIOSSLContext (server-mode) using a freshly minted leaf cert + key for `host`.
    /// Called from ProxyRequestHandler on the NIO event loop (dispatched via Task to @MainActor).
    func niosslContext(for host: String) throws -> NIOSSLContext {
        let pair = try leafCertificate(for: host)
        let leafPEM = try pair.certificate.serializeAsPEM().pemString
        let keyPEM  = try Certificate.PrivateKey(pair.key).serializeAsPEM().pemString
        let nioLeaf = try NIOSSLCertificate(bytes: Array(leafPEM.utf8), format: .pem)
        let nioKey  = try NIOSSLPrivateKey(bytes: Array(keyPEM.utf8), format: .pem)

        // Include CA in chain so client can build trust path.
        // (Browsers don't strictly require this if CA is in their trust store,
        // but Chrome/Safari handle it more reliably this way.)
        var chain: [NIOSSLCertificateSource] = [.certificate(nioLeaf)]
        if let caCert = ca.certificate {
            let caPEM = try caCert.serializeAsPEM().pemString
            let nioCA = try NIOSSLCertificate(bytes: Array(caPEM.utf8), format: .pem)
            chain.append(.certificate(nioCA))
        }

        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: chain,
            privateKey: .privateKey(nioKey)
        )
        config.minimumTLSVersion = .tlsv12
        // ALPN: advertise http/1.1 only. We don't yet handle h2 over TLS.
        config.applicationProtocols = ["http/1.1"]
        return try NIOSSLContext(configuration: config)
    }
}
