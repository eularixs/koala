import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var projectId: UUID
    var requestSnapshot: KoalaRequest
    var responseSnapshot: KoalaResponse?
    var sentAt: Date
    var success: Bool

    init(
        id: UUID = UUID(),
        projectId: UUID = UUID(),
        requestSnapshot: KoalaRequest,
        responseSnapshot: KoalaResponse?,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.requestSnapshot = requestSnapshot
        self.responseSnapshot = responseSnapshot
        self.sentAt = sentAt
        self.success = responseSnapshot?.isSuccess ?? false
    }

    // MARK: Backwards-compatible decode (missing projectId -> zero UUID)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = (try? c.decodeIfPresent(UUID.self, forKey: .projectId)) ?? UUID()
        requestSnapshot = try c.decode(KoalaRequest.self, forKey: .requestSnapshot)
        responseSnapshot = try c.decodeIfPresent(KoalaResponse.self, forKey: .responseSnapshot)
        sentAt = try c.decode(Date.self, forKey: .sentAt)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
    }
}
