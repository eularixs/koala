import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var requestSnapshot: KoalaRequest
    var responseSnapshot: KoalaResponse?
    var sentAt: Date
    var success: Bool

    init(
        id: UUID = UUID(),
        requestSnapshot: KoalaRequest,
        responseSnapshot: KoalaResponse?,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.requestSnapshot = requestSnapshot
        self.responseSnapshot = responseSnapshot
        self.sentAt = sentAt
        self.success = responseSnapshot?.isSuccess ?? false
    }
}
