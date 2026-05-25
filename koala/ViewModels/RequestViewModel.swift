import Foundation
import Observation

// MARK: - Supporting enums

enum BodyTab: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case pretty = "Pretty"
    case preview = "Preview"

    var id: String { rawValue }
}

enum ResponseTab: String, CaseIterable, Identifiable {
    case body = "Body"
    case headers = "Headers"
    case cookies = "Cookies"
    case timeline = "Timeline"

    var id: String { rawValue }
}

// MARK: - RequestViewModel

@MainActor
@Observable
final class RequestViewModel {
    var response: KoalaResponse? = nil
    var isSending: Bool = false
    var lastError: String? = nil
    var curlCommand: String = ""
    var selectedBodyTab: BodyTab = .pretty
    var selectedResponseTab: ResponseTab = .body

    private let httpClient: HTTPClientService

    init(httpClient: HTTPClientService = HTTPClientService()) {
        self.httpClient = httpClient
    }

    func send(_ request: KoalaRequest, environment: KoalaEnvironment? = nil, globalVariables: [KeyValuePair] = []) async {
        isSending = true
        lastError = nil
        defer { isSending = false }

        do {
            response = try await httpClient.send(request, environment: environment, globalVariables: globalVariables)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func generateCurlCommand(_ request: KoalaRequest, environment: KoalaEnvironment? = nil, globalVariables: [KeyValuePair] = []) {
        curlCommand = httpClient.curlCommand(for: request, environment: environment, globalVariables: globalVariables)
    }
}
