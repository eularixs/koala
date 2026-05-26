import Foundation
import Observation

// MARK: - Errors

enum GraphQLIntrospectionError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case schemaParseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GraphQL endpoint URL is invalid."
        case .networkError(let s):
            return "Network error: \(s)"
        case .schemaParseError(let s):
            return "Failed to parse schema: \(s)"
        }
    }
}

// MARK: - Introspector

@MainActor
@Observable
final class GraphQLIntrospector {
    var isLoading: Bool = false
    var lastError: String? = nil
    var schema: GraphQLSchema? = nil

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func introspect(url: String, headers: [KeyValuePair]) async throws -> GraphQLSchema {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed), !trimmed.isEmpty else {
            throw GraphQLIntrospectionError.invalidURL
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        for h in headers where h.isEnabled && !h.key.isEmpty {
            req.setValue(h.value, forHTTPHeaderField: h.key)
        }

        let payload: [String: Any] = ["query": GraphQLSchema.query]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw GraphQLIntrospectionError.networkError("Failed to serialize introspection request")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let msg = error.localizedDescription
            lastError = msg
            throw GraphQLIntrospectionError.networkError(msg)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = "HTTP \(http.statusCode)"
            lastError = msg
            throw GraphQLIntrospectionError.networkError(msg)
        }

        do {
            let parsed = try GraphQLSchema.parse(data)
            schema = parsed
            lastError = nil
            return parsed
        } catch let e as GraphQLIntrospectionError {
            lastError = e.errorDescription
            throw e
        } catch {
            lastError = error.localizedDescription
            throw GraphQLIntrospectionError.schemaParseError(error.localizedDescription)
        }
    }

    func reset() {
        schema = nil
        lastError = nil
        isLoading = false
    }
}
