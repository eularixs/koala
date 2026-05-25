import Foundation

// MARK: - EnvVariable

struct EnvVariable: Identifiable, Codable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isSecret: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
    }

    static var empty: EnvVariable { EnvVariable() }
}

// MARK: - KoalaEnvironment

/// Named `KoalaEnvironment` to avoid collision with SwiftUI's `Environment` property wrapper.
struct KoalaEnvironment: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var variables: [EnvVariable]
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String = "New Environment",
        variables: [EnvVariable] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.variables = variables
        self.isActive = isActive
    }

    static var empty: KoalaEnvironment { KoalaEnvironment() }

    /// Resolve a variable name, returning nil if not found or not enabled.
    func resolve(_ key: String) -> String? {
        variables.first(where: { $0.key == key && $0.isEnabled })?.value
    }
}
