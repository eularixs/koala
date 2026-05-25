import Foundation

enum HTTPClientError: Error, LocalizedError {
    case invalidURL
    case malformedRequest(String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .malformedRequest(let reason):
            return "Malformed request: \(reason)"
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        }
    }
}

private final class MetricsDelegate: NSObject, URLSessionTaskDelegate {
    var timeline: ResponseTimeline = .zero

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let phase = metrics.transactionMetrics.first else { return }

        func ms(_ start: Date?, _ end: Date?) -> Int {
            guard let s = start, let e = end else { return 0 }
            return Int(e.timeIntervalSince(s) * 1000)
        }

        timeline = ResponseTimeline(
            dnsMs: ms(phase.domainLookupStartDate, phase.domainLookupEndDate),
            connectMs: ms(phase.connectStartDate, phase.connectEndDate),
            tlsMs: ms(phase.secureConnectionStartDate, phase.secureConnectionEndDate),
            ttfbMs: ms(phase.requestStartDate, phase.responseStartDate),
            downloadMs: ms(phase.responseStartDate, phase.responseEndDate)
        )
    }
}

@MainActor
final class HTTPClientService: ObservableObject {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(
        _ request: KoalaRequest,
        environment: KoalaEnvironment? = nil,
        globalVariables: [KeyValuePair] = []
    ) async throws -> KoalaResponse {
        let resolved = VariableResolver.resolveAll(in: request, environment: environment, globals: globalVariables)
        let urlRequest = try buildURLRequest(from: resolved)

        let delegate = MetricsDelegate()
        let delegateSession = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil
        )

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await delegateSession.data(for: urlRequest)
        } catch {
            throw HTTPClientError.transport(error)
        }
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.transport(
                NSError(domain: "HTTPClientService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response received."])
            )
        }

        let headers = Dictionary(
            uniqueKeysWithValues: http.allHeaderFields.compactMap { k, v -> (String, String)? in
                guard let key = k as? String, let value = v as? String else { return nil }
                return (key, value)
            }
        )

        return KoalaResponse(
            statusCode: http.statusCode,
            statusText: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
            headers: headers,
            body: data,
            durationMs: durationMs,
            sizeBytes: data.count,
            timeline: delegate.timeline
        )
    }

    func curlCommand(
        for request: KoalaRequest,
        environment: KoalaEnvironment?,
        globalVariables: [KeyValuePair]
    ) -> String {
        let resolved = VariableResolver.resolveAll(in: request, environment: environment, globals: globalVariables)
        var parts: [String] = ["curl"]

        parts.append("-X \(resolved.method.rawValue)")

        for header in resolved.headers where header.isEnabled && !header.key.isEmpty {
            let escaped = header.value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(header.key): \(escaped)'")
        }

        if let bodyString = curlBodyArgument(for: resolved.body) {
            parts.append(bodyString)
        }

        if let urlString = buildURLString(from: resolved), let url = URL(string: urlString) {
            parts.append("'\(url.absoluteString)'")
        } else {
            parts.append("'\(resolved.url)'")
        }

        return parts.joined(separator: " \\\n  ")
    }

    private func buildURLRequest(from request: KoalaRequest) throws -> URLRequest {
        guard let urlString = buildURLString(from: request), let url = URL(string: urlString) else {
            throw HTTPClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        for header in request.headers where header.isEnabled && !header.key.isEmpty {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }

        try applyAuth(request.auth, to: &urlRequest)
        try applyBody(request.body, to: &urlRequest)

        return urlRequest
    }

    private func buildURLString(from request: KoalaRequest) -> String? {
        let rawURL = request.url.trimmingCharacters(in: .whitespaces)
        guard !rawURL.isEmpty else { return nil }

        let enabledParams = request.queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        guard !enabledParams.isEmpty else { return rawURL }

        guard var components = URLComponents(string: rawURL) else { return rawURL }
        var items = components.queryItems ?? []
        for param in enabledParams {
            items.append(URLQueryItem(name: param.key, value: param.value))
        }
        components.queryItems = items
        return components.string ?? rawURL
    }

    private func applyAuth(_ auth: AuthConfig, to request: inout URLRequest) throws {
        switch auth {
        case .none:
            break

        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        case .basic(let username, let password):
            let credentials = "\(username):\(password)"
            guard let data = credentials.data(using: .utf8) else {
                throw HTTPClientError.malformedRequest("Basic auth credentials are not UTF-8 encodable.")
            }
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")

        case .apiKey(let key, let value, let location):
            switch location {
            case .header:
                request.setValue(value, forHTTPHeaderField: key)
            case .query:
                guard let currentURL = request.url,
                      var components = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
                else { throw HTTPClientError.invalidURL }
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: key, value: value))
                components.queryItems = items
                request.url = components.url
            }

        case .oauth2:
            // TODO: OAuth 2.0 token injection
            break

        case .awsSignature:
            // TODO: AWS Signature V4 signing
            break
        }
    }

    private func applyBody(_ body: RequestBody, to request: inout URLRequest) throws {
        switch body {
        case .none:
            break

        case .json(let string):
            guard let data = string.data(using: .utf8) else {
                throw HTTPClientError.malformedRequest("JSON body is not UTF-8 encodable.")
            }
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        case .raw(let content, let contentType):
            guard let data = content.data(using: .utf8) else {
                throw HTTPClientError.malformedRequest("Raw body is not UTF-8 encodable.")
            }
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        case .formURLEncoded(let pairs):
            var components = URLComponents()
            components.queryItems = pairs
                .filter { $0.isEnabled }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            let encoded = components.percentEncodedQuery ?? ""
            request.httpBody = encoded.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        case .multipart(let items):
            let (data, boundary) = try buildMultipartBody(items)
            request.httpBody = data
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        case .graphql(let query, let variables):
            var payload: [String: Any] = ["query": query]
            if !variables.isEmpty,
               let obj = try? JSONSerialization.jsonObject(with: Data(variables.utf8)) {
                payload["variables"] = obj
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        case .binary(let fileURL):
            request.httpBody = try Data(contentsOf: fileURL)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
    }

    private func buildMultipartBody(_ items: [MultipartItem]) throws -> (Data, String) {
        let boundary = "KoalaBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        let crlf = "\r\n"

        for item in items where !item.key.isEmpty {
            body.append("--\(boundary)\(crlf)".utf8Data)

            switch item.type {
            case .text:
                let disposition = "Content-Disposition: form-data; name=\"\(item.key)\""
                body.append("\(disposition)\(crlf)\(crlf)".utf8Data)
                body.append(item.value.utf8Data)
                body.append(crlf.utf8Data)

            case .file:
                guard let fileURL = item.fileURL else {
                    throw HTTPClientError.malformedRequest("Multipart file item missing fileURL.")
                }
                let filename = fileURL.lastPathComponent
                let disposition = "Content-Disposition: form-data; name=\"\(item.key)\"; filename=\"\(filename)\""
                body.append("\(disposition)\(crlf)".utf8Data)
                body.append("Content-Type: application/octet-stream\(crlf)\(crlf)".utf8Data)
                body.append(try Data(contentsOf: fileURL))
                body.append(crlf.utf8Data)
            }
        }
        body.append("--\(boundary)--\(crlf)".utf8Data)
        return (body, boundary)
    }

    private func curlBodyArgument(for body: RequestBody) -> String? {
        switch body {
        case .none:
            return nil
        case .json(let s):
            let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
            return "--data '\(escaped)'"
        case .raw(let s, _):
            let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
            return "--data '\(escaped)'"
        case .formURLEncoded(let pairs):
            let encoded = pairs
                .filter { $0.isEnabled }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            return "--data-urlencode '\(encoded)'"
        case .multipart(let items):
            let args = items
                .filter { !$0.key.isEmpty }
                .map { item -> String in
                    switch item.type {
                    case .text:
                        return "-F '\(item.key)=\(item.value)'"
                    case .file:
                        let path = item.fileURL?.path ?? "<file>"
                        return "-F '\(item.key)=@\(path)'"
                    }
                }
            return args.joined(separator: " \\\n  ")
        case .graphql(let query, let variables):
            var payload: [String: Any] = ["query": query]
            if !variables.isEmpty { payload["variables"] = variables }
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8) {
                let escaped = str.replacingOccurrences(of: "'", with: "'\\''")
                return "--data '\(escaped)'"
            }
            return nil
        case .binary(let fileURL):
            return "--data-binary @\(fileURL.path)"
        }
    }
}

private extension String {
    var utf8Data: Data { data(using: .utf8) ?? Data() }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
