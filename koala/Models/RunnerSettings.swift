import Foundation

/// Per-request SLA + snapshot config. Keyed by request UUID, stored in AppState
/// separately so KoalaRequest schema stays untouched.
struct RunnerSettings: Identifiable, Codable, Hashable {
    var id: UUID                    // == request.id
    var slaThresholdMs: Int?        // warn if response slower than this
    var expectedStatusCode: Int?    // if set, mismatch = fail
    var jsonSnapshot: String?       // golden JSON; assertion compares response to this
    var enabledInRun: Bool = true

    init(
        id: UUID,
        slaThresholdMs: Int? = nil,
        expectedStatusCode: Int? = nil,
        jsonSnapshot: String? = nil,
        enabledInRun: Bool = true
    ) {
        self.id = id
        self.slaThresholdMs = slaThresholdMs
        self.expectedStatusCode = expectedStatusCode
        self.jsonSnapshot = jsonSnapshot
        self.enabledInRun = enabledInRun
    }

    // MARK: Backwards-compatible decode
    enum CodingKeys: String, CodingKey {
        case id, slaThresholdMs, expectedStatusCode, jsonSnapshot, enabledInRun
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slaThresholdMs = try c.decodeIfPresent(Int.self, forKey: .slaThresholdMs)
        expectedStatusCode = try c.decodeIfPresent(Int.self, forKey: .expectedStatusCode)
        jsonSnapshot = try c.decodeIfPresent(String.self, forKey: .jsonSnapshot)
        enabledInRun = (try? c.decodeIfPresent(Bool.self, forKey: .enabledInRun)) ?? true
    }
}
