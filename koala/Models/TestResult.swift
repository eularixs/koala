import Foundation

/// Result of a single `koala.test(...)` assertion executed by `ScriptingService`.
struct TestResult: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var passed: Bool
    var failureMessage: String?
    var durationMs: Int

    init(
        id: UUID = UUID(),
        name: String,
        passed: Bool,
        failureMessage: String? = nil,
        durationMs: Int = 0
    ) {
        self.id = id
        self.name = name
        self.passed = passed
        self.failureMessage = failureMessage
        self.durationMs = durationMs
    }
}
