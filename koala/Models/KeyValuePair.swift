import Foundation

struct KeyValuePair: Identifiable, Codable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var description: String
    var isEnabled: Bool
    var isSecret: Bool

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        description: String = "",
        isEnabled: Bool = true,
        isSecret: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.description = description
        self.isEnabled = isEnabled
        self.isSecret = isSecret
    }

    static var empty: KeyValuePair {
        KeyValuePair()
    }
}
