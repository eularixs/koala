import NIO
import NIOHTTP1
import NIOSSL
import Foundation

// MARK: - ProxyRequestHandler
//
// NIO ChannelInboundHandler for one HTTP/1.1 connection (plain or MITM-decrypted TLS).
//
// Pipeline (initial, HTTP):
//   [ByteToMessageHandler<HTTPDecoder>] → [HTTPResponseEncoder] → [ProxyRequestHandler]
//
// Pipeline after CONNECT MITM upgrade:
//   [NIOSSLServerHandler] → [ByteToMessageHandler<HTTPDecoder>(fresh)] → [HTTPResponseEncoder(fresh)] → [ProxyRequestHandler(fresh)]
//
// The upgrade path removes the old codecs and self, swaps in SSL + fresh instances.

final class ProxyRequestHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn  = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private weak var service: RecordingProxyService?

    private var currentHead: HTTPRequestHead?
    private var currentBody: ByteBuffer?

    // Stored so the TLS upgrade can remove the old codecs by reference.
    private var httpDecoder: RemovableChannelHandler?
    private var httpEncoder: RemovableChannelHandler?

    // Set after CONNECT so the forward-proxy resolver can reconstruct https://host/path.
    var connectHost: String?

    init(service: RecordingProxyService,
         httpDecoder: RemovableChannelHandler? = nil,
         httpEncoder: RemovableChannelHandler? = nil) {
        self.service = service
        self.httpDecoder = httpDecoder
        self.httpEncoder = httpEncoder
    }

    // MARK: Channel read

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            currentHead = head
            currentBody = nil
            if head.method == .CONNECT {
                handleConnect(head: head, context: context)
            }

        case .body(var buf):
            if currentBody == nil { currentBody = buf }
            else { currentBody!.writeBuffer(&buf) }

        case .end:
            guard let head = currentHead, head.method != .CONNECT else { return }
            handlePlainHTTP(head: head, body: currentBody, context: context)
            currentHead = nil
            currentBody = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[Koala Proxy] errorCaught host=\(connectHost ?? "-"): \(error)")
        context.close(promise: nil)
    }

    // MARK: CONNECT handling

    private func handleConnect(head: HTTPRequestHead, context: ChannelHandlerContext) {
        print("[Koala Proxy] CONNECT received: \(head.uri)")

        // head.uri format: "host:port" per RFC 7231 §4.3.6
        let target = head.uri
        let parts  = target.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty else {
            sendErrorOnEventLoop(context: context, status: .badRequest,
                                 message: "Bad CONNECT target: \(target)")
            return
        }
        let host = String(parts[0])

        // CRITICAL: pause autoRead BEFORE writing the 200 response. Otherwise
        // the browser sees 200 OK and immediately starts sending TLS ClientHello,
        // which arrives at the OLD HTTPDecoder (still in pipeline) and gets
        // parsed as "invalid HTTP method" → connection breaks.
        let channel = context.channel
        channel.setOption(ChannelOptions.autoRead, value: false).whenComplete { [weak self] _ in
            // Send 200 Connection Established
            var hdrs = HTTPHeaders()
            hdrs.add(name: "Content-Length", value: "0")
            let response = HTTPResponseHead(
                version: .init(major: 1, minor: 1),
                status: .init(statusCode: 200, reasonPhrase: "Connection Established"),
                headers: hdrs
            )
            context.write(self?.wrapOutboundOut(.head(response)) ?? NIOAny(()), promise: nil)
            context.writeAndFlush(self?.wrapOutboundOut(.end(nil)) ?? NIOAny(())).whenComplete { _ in
                // Now swap pipeline → insert SSL handler + fresh codecs.
                // performPipelineSwap re-enables autoRead at the end.
                self?.upgradeToTLS(host: host, context: context)
            }
        }
    }

    // MARK: TLS pipeline swap

    private func upgradeToTLS(host: String, context: ChannelHandlerContext) {
        Task { @MainActor [weak self] in
            guard let self, let svc = self.service else { return }
            do {
                print("[Koala Proxy] minting cert for \(host)")
                let sslContext = try SecurityServices.certMinter.niosslContext(for: host)
                print("[Koala Proxy] minted OK for \(host), inserting SSL handler")
                let sslHandler = NIOSSLServerHandler(context: sslContext)
                let oldDecoder = self.httpDecoder
                let oldEncoder = self.httpEncoder

                context.eventLoop.execute {
                    self.performPipelineSwap(
                        sslHandler: sslHandler,
                        host: host,
                        service: svc,
                        oldDecoder: oldDecoder,
                        oldEncoder: oldEncoder,
                        context: context
                    )
                }
            } catch {
                print("[Koala Proxy] cert mint FAILED for \(host): \(error)")
                context.eventLoop.execute {
                    self.sendErrorOnEventLoop(
                        context: context, status: .internalServerError,
                        message: "Cert mint failed for \(host): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    // Must run on the event loop.
    //
    // CRITICAL ORDER: old codecs + self MUST be removed BEFORE SSL handler
    // emits any decrypted bytes downstream, otherwise raw ByteBuffer flows
    // into the stale ProxyRequestHandler (which expects HTTPPart) → crash:
    //   "tried to decode as type HTTPPart<HTTPRequestHead, ByteBuffer>
    //    but found IOData ..."
    //
    // Strategy: pause autoRead, atomically remove old handlers + add fresh
    // ones via syncOperations, then resume autoRead.
    private func performPipelineSwap(
        sslHandler: NIOSSLServerHandler,
        host: String,
        service: RecordingProxyService,
        oldDecoder: RemovableChannelHandler?,
        oldEncoder: RemovableChannelHandler?,
        context: ChannelHandlerContext
    ) {
        let channel = context.channel
        let pipeline = channel.pipeline

        let freshDecoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
        let freshEncoder = HTTPResponseEncoder()
        let freshHandler = ProxyRequestHandler(service: service,
                                               httpDecoder: freshDecoder,
                                               httpEncoder: freshEncoder)
        freshHandler.connectHost = host

        // We're already on the event loop (called from context.eventLoop.execute).
        // Do everything synchronously to avoid race where TLS bytes arrive
        // before pipeline is restructured.
        let sync = pipeline.syncOperations
        do {
            // Remove old HTTP codecs + this handler. ORDER: codecs first, then self.
            // Removing self last keeps `context` valid for the prior removals.
            if let dec = oldDecoder { try sync.removeHandler(dec) }
            if let enc = oldEncoder { try sync.removeHandler(enc) }
            try sync.removeHandler(self)

            // Add SSL at .first so raw network bytes enter SSL → emit decrypted bytes
            // downstream to the fresh HTTPDecoder.
            try sync.addHandler(sslHandler, position: .first)
            try sync.addHandler(freshDecoder)
            try sync.addHandler(freshEncoder)
            try sync.addHandler(freshHandler)
        } catch {
            print("[Koala Proxy] performPipelineSwap FAILED for \(host): \(error)")
            channel.close(promise: nil)
            return
        }
        print("[Koala Proxy] pipeline swap done for \(host), waiting for TLS handshake")
        // Resume reads — SSL handler now in place to consume TLS bytes.
        channel.setOption(ChannelOptions.autoRead, value: true).whenFailure { err in
            print("[Koala Proxy] autoRead resume FAILED for \(host): \(err)")
        }
    }

    // MARK: Plain HTTP (initial + post-MITM decrypted stream)

    private func handlePlainHTTP(head: HTTPRequestHead, body: ByteBuffer?, context: ChannelHandlerContext) {
        Task { @MainActor [weak self] in
            guard let self, let svc = self.service else { return }
            let result = await svc.processHTTPRequest(head: head, body: body, connectHost: self.connectHost)
            let version = head.version
            context.eventLoop.execute {
                self.writeResult(result, version: version, context: context)
            }
        }
    }

    // MARK: Write helpers

    private func writeResult(_ result: ProxyResult, version: HTTPVersion, context: ChannelHandlerContext) {
        var hdrs = HTTPHeaders()
        for (k, v) in result.headers { hdrs.add(name: k, value: v) }

        let head = HTTPResponseHead(
            version: version,
            status: HTTPResponseStatus(statusCode: result.status),
            headers: hdrs
        )
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if !result.body.isEmpty {
            var buf = context.channel.allocator.buffer(capacity: result.body.count)
            buf.writeBytes(result.body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        }

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    // Must be called on the event loop.
    fileprivate func sendErrorOnEventLoop(context: ChannelHandlerContext,
                                          status: HTTPResponseStatus,
                                          message: String) {
        var hdrs = HTTPHeaders()
        hdrs.add(name: "Content-Length", value: "\(message.utf8.count)")
        hdrs.add(name: "Connection", value: "close")
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: status, headers: hdrs)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: message.utf8.count)
        buf.writeString(message)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
