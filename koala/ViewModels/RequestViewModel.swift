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
    case tests = "Tests"
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
    private let scripting: ScriptingService
    /// Optional cookie jar; if set + envId provided to `send`, cookies are
    /// auto-attached on outgoing requests and Set-Cookie responses are ingested.
    var cookieJar: CookieJarService? = nil
    /// Optional vault service. When set + `projectId` passed to `send`, vault
    /// variables (`{{secret.X}}`-style) are resolved from Keychain at send time.
    var vaultService: VaultService? = nil
    var projectId: UUID? = nil

    /// Optional callback invoked when a script mutates the current environment.
    /// Wired by `RequestEditorView` so changes are persisted via `AppState`.
    var onEnvMutated: ((KoalaEnvironment) -> Void)?
    /// Optional callback invoked when a script mutates the globals list.
    var onGlobalsMutated: (([KeyValuePair]) -> Void)?
    /// Optional callback invoked when the pre-request script mutates the request itself.
    var onRequestMutated: ((KoalaRequest) -> Void)?

    init(
        httpClient: HTTPClientService = HTTPClientService(),
        scripting: ScriptingService? = nil,
        onEnvMutated: ((KoalaEnvironment) -> Void)? = nil,
        onGlobalsMutated: (([KeyValuePair]) -> Void)? = nil,
        onRequestMutated: ((KoalaRequest) -> Void)? = nil
    ) {
        self.httpClient = httpClient
        self.scripting = scripting ?? ScriptingService()
        self.onEnvMutated = onEnvMutated
        self.onGlobalsMutated = onGlobalsMutated
        self.onRequestMutated = onRequestMutated
    }

    func send(_ request: KoalaRequest, environment: KoalaEnvironment? = nil, globalVariables: [KeyValuePair] = [], envId: UUID? = nil) async {
        isSending = true
        lastError = nil
        defer { isSending = false }

        var workingRequest = request
        var workingEnv = environment
        var workingGlobals = globalVariables
        var preLogs: [String] = []

        // --- Pre-request script ---
        if let pre = workingRequest.preRequestScript,
           !pre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                preLogs = try scripting.runPreRequest(
                    script: pre,
                    request: &workingRequest,
                    env: &workingEnv,
                    globals: &workingGlobals
                )
                if workingRequest != request { onRequestMutated?(workingRequest) }
                if let e = workingEnv, e != environment { onEnvMutated?(e) }
                if workingGlobals != globalVariables { onGlobalsMutated?(workingGlobals) }
            } catch {
                lastError = "Pre-request script: \(error.localizedDescription)"
                return
            }
        }

        // --- Cookie pre-attach ---
        var cookieHeader: String? = nil
        if let jar = cookieJar, let eid = envId,
           let resolvedURL = URL(string: VariableResolver.resolve(workingRequest.url, environment: workingEnv, globals: workingGlobals)) {
            cookieHeader = jar.headerValueMatching(url: resolvedURL, forEnv: eid)
        }

        // --- HTTP send ---
        var httpResponse: KoalaResponse
        var rawSetCookies: [String] = []
        do {
            if cookieHeader != nil || cookieJar != nil {
                let result = try await httpClient.sendDetailed(
                    workingRequest,
                    environment: workingEnv,
                    globalVariables: workingGlobals,
                    cookieHeader: cookieHeader,
                    vault: vaultService,
                    projectId: projectId
                )
                httpResponse = result.response
                rawSetCookies = result.rawSetCookieHeaders
            } else {
                httpResponse = try await httpClient.send(
                    workingRequest,
                    environment: workingEnv,
                    globalVariables: workingGlobals,
                    vault: vaultService,
                    projectId: projectId
                )
            }
        } catch {
            lastError = error.localizedDescription
            return
        }

        // --- Cookie ingest ---
        if let jar = cookieJar, let eid = envId,
           let resolvedURL = URL(string: VariableResolver.resolve(workingRequest.url, environment: workingEnv, globals: workingGlobals)) {
            for header in rawSetCookies {
                jar.ingest(setCookieHeader: header, requestURL: resolvedURL, forEnv: eid)
            }
        }

        // --- Post-response / tests ---
        if let test = workingRequest.testScript,
           !test.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let (logs, tests) = try scripting.runPostResponse(
                    script: test,
                    request: workingRequest,
                    response: httpResponse,
                    env: &workingEnv,
                    globals: &workingGlobals
                )
                httpResponse.consoleLogs = preLogs + logs
                httpResponse.testResults = tests
                if let e = workingEnv, e != environment { onEnvMutated?(e) }
                if workingGlobals != globalVariables { onGlobalsMutated?(workingGlobals) }
            } catch {
                httpResponse.consoleLogs = preLogs
                httpResponse.testResults = [
                    TestResult(name: "Test script error", passed: false,
                               failureMessage: error.localizedDescription, durationMs: 0)
                ]
            }
        } else {
            httpResponse.consoleLogs = preLogs
        }

        response = httpResponse
    }

    func generateCurlCommand(_ request: KoalaRequest, environment: KoalaEnvironment? = nil, globalVariables: [KeyValuePair] = []) {
        curlCommand = httpClient.curlCommand(for: request, environment: environment, globalVariables: globalVariables)
    }
}
