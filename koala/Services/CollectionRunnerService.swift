import Foundation
import Observation

// MARK: - RequestRunResult

struct RequestRunResult: Identifiable, Codable, Hashable {
    let id: UUID
    let requestId: UUID
    let requestName: String
    let statusCode: Int?
    let durationMs: Int
    let passed: Bool
    let slaViolation: Bool
    let testResults: [TestResult]
    let snapshotDiff: String?  // nil if no snapshot or matches
    let error: String?

    init(
        id: UUID = UUID(),
        requestId: UUID,
        requestName: String,
        statusCode: Int?,
        durationMs: Int,
        passed: Bool,
        slaViolation: Bool,
        testResults: [TestResult],
        snapshotDiff: String?,
        error: String?
    ) {
        self.id = id
        self.requestId = requestId
        self.requestName = requestName
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.passed = passed
        self.slaViolation = slaViolation
        self.testResults = testResults
        self.snapshotDiff = snapshotDiff
        self.error = error
    }
}

// MARK: - CollectionRunnerService

@MainActor
@Observable
final class CollectionRunnerService {

    enum RunStatus: Equatable {
        case idle, running, completed, cancelled
    }

    var status: RunStatus = .idle
    var progress: (current: Int, total: Int) = (0, 0)
    var results: [RequestRunResult] = []

    private let httpClient: HTTPClientService
    private let scripting: ScriptingService
    private var currentTask: Task<Void, Never>? = nil

    init(
        httpClient: HTTPClientService = HTTPClientService(),
        scripting: ScriptingService? = nil
    ) {
        self.httpClient = httpClient
        self.scripting = scripting ?? ScriptingService()
    }

    // MARK: - Run

    func run(
        collection: KoalaCollection,
        settings: [UUID: RunnerSettings],
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) async {
        // Cancel any prior task
        currentTask?.cancel()

        results = []
        let requests = Self.flatten(items: collection.items)
        let activeRequests = requests.filter { req in
            (settings[req.id]?.enabledInRun ?? true)
        }
        progress = (0, activeRequests.count)
        status = .running

        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeSequentially(
                requests: activeRequests,
                settings: settings,
                environment: environment,
                globals: globals
            )
        }
        currentTask = task
        await task.value
    }

    func cancel() {
        currentTask?.cancel()
        if status == .running {
            status = .cancelled
        }
    }

    // MARK: - Internal sequential execution

    private func executeSequentially(
        requests: [KoalaRequest],
        settings: [UUID: RunnerSettings],
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) async {
        var workingEnv = environment
        var workingGlobals = globals

        for (idx, req) in requests.enumerated() {
            if Task.isCancelled {
                status = .cancelled
                return
            }
            progress = (idx, requests.count)

            let setting = settings[req.id]
            let result = await runOne(
                request: req,
                setting: setting,
                environment: &workingEnv,
                globals: &workingGlobals
            )
            results.append(result)
            progress = (idx + 1, requests.count)
        }

        if Task.isCancelled {
            status = .cancelled
        } else {
            status = .completed
        }
    }

    private func runOne(
        request original: KoalaRequest,
        setting: RunnerSettings?,
        environment: inout KoalaEnvironment?,
        globals: inout [KeyValuePair]
    ) async -> RequestRunResult {
        var workingRequest = original
        var preLogs: [String] = []

        // Pre-request script
        if let pre = workingRequest.preRequestScript,
           !pre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                preLogs = try scripting.runPreRequest(
                    script: pre,
                    request: &workingRequest,
                    env: &environment,
                    globals: &globals
                )
            } catch {
                return RequestRunResult(
                    requestId: original.id,
                    requestName: original.name,
                    statusCode: nil,
                    durationMs: 0,
                    passed: false,
                    slaViolation: false,
                    testResults: [],
                    snapshotDiff: nil,
                    error: "Pre-request script: \(error.localizedDescription)"
                )
            }
        }

        // HTTP send
        var response: KoalaResponse
        do {
            response = try await httpClient.send(
                workingRequest,
                environment: environment,
                globalVariables: globals
            )
        } catch {
            return RequestRunResult(
                requestId: original.id,
                requestName: original.name,
                statusCode: nil,
                durationMs: 0,
                passed: false,
                slaViolation: false,
                testResults: [],
                snapshotDiff: nil,
                error: error.localizedDescription
            )
        }

        // Post-response / tests
        var testResults: [TestResult] = []
        if let testScript = workingRequest.testScript,
           !testScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let (logs, tests) = try scripting.runPostResponse(
                    script: testScript,
                    request: workingRequest,
                    response: response,
                    env: &environment,
                    globals: &globals
                )
                response.consoleLogs = preLogs + logs
                response.testResults = tests
                testResults = tests
            } catch {
                testResults = [
                    TestResult(
                        name: "Test script error",
                        passed: false,
                        failureMessage: error.localizedDescription,
                        durationMs: 0
                    )
                ]
            }
        }

        // Expected status code check
        var statusFail: String? = nil
        if let expected = setting?.expectedStatusCode, expected != response.statusCode {
            statusFail = "Expected status \(expected), got \(response.statusCode)"
            testResults.append(TestResult(
                name: "Expected status code",
                passed: false,
                failureMessage: statusFail,
                durationMs: 0
            ))
        }

        // SLA check
        let slaViolation: Bool
        if let sla = setting?.slaThresholdMs {
            slaViolation = response.durationMs > sla
        } else {
            slaViolation = false
        }

        // Snapshot diff
        var snapshotDiff: String? = nil
        if let snapshot = setting?.jsonSnapshot,
           !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshotDiff = Self.compareJSONSnapshot(expected: snapshot, actual: response.body)
        }

        // Overall pass: tests all passed, status matched if specified, snapshot matched
        let allTestsPassed = testResults.allSatisfy { $0.passed }
        let passed = allTestsPassed && statusFail == nil && snapshotDiff == nil

        return RequestRunResult(
            requestId: original.id,
            requestName: original.name,
            statusCode: response.statusCode,
            durationMs: response.durationMs,
            passed: passed,
            slaViolation: slaViolation,
            testResults: testResults,
            snapshotDiff: snapshotDiff,
            error: nil
        )
    }

    // MARK: - Tree flattening

    static func flatten(items: [CollectionItem]) -> [KoalaRequest] {
        var out: [KoalaRequest] = []
        for item in items {
            switch item {
            case .request(let r):
                out.append(r)
            case .folder(let f):
                out.append(contentsOf: flatten(items: f.items))
            }
        }
        return out
    }

    // MARK: - JSON snapshot comparison

    /// Returns nil if JSON matches structurally (key order normalized), otherwise
    /// returns a human-readable diff string.
    static func compareJSONSnapshot(expected: String, actual: Data) -> String? {
        guard let expectedData = expected.data(using: .utf8) else {
            return "Snapshot is not valid UTF-8"
        }

        let expectedObj: Any
        let actualObj: Any
        do {
            expectedObj = try JSONSerialization.jsonObject(with: expectedData, options: [.fragmentsAllowed])
        } catch {
            return "Snapshot is not valid JSON: \(error.localizedDescription)"
        }
        do {
            actualObj = try JSONSerialization.jsonObject(with: actual, options: [.fragmentsAllowed])
        } catch {
            let actualStr = String(data: actual, encoding: .utf8) ?? "<binary>"
            return "Response is not valid JSON.\n--- Expected ---\n\(expected)\n--- Actual ---\n\(actualStr)"
        }

        if deepEqual(expectedObj, actualObj) {
            return nil
        }

        // Build normalized diff
        let normExpected = canonicalString(expectedObj) ?? expected
        let normActual = canonicalString(actualObj) ?? (String(data: actual, encoding: .utf8) ?? "")
        return "--- Expected ---\n\(normExpected)\n--- Actual ---\n\(normActual)"
    }

    /// Stable JSON string with sorted keys.
    private static func canonicalString(_ obj: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(obj) || obj is NSNull || obj is NSNumber || obj is String else {
            // For fragments, wrap
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted, .fragmentsAllowed]) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted, .fragmentsAllowed]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func deepEqual(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            if a.keys.sorted() != b.keys.sorted() { return false }
            for (k, v) in a {
                guard let bv = b[k] else { return false }
                if !deepEqual(v, bv) { return false }
            }
            return true
        }
        if let a = a as? [Any], let b = b as? [Any] {
            if a.count != b.count { return false }
            for i in 0..<a.count {
                if !deepEqual(a[i], b[i]) { return false }
            }
            return true
        }
        if let a = a as? NSNumber, let b = b as? NSNumber {
            return a == b
        }
        if let a = a as? String, let b = b as? String {
            return a == b
        }
        if a is NSNull && b is NSNull { return true }
        return String(describing: a) == String(describing: b)
    }
}
