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
    var projectId: UUID
    var name: String
    var variables: [EnvVariable]
    var isActive: Bool

    init(
        id: UUID = UUID(),
        projectId: UUID = UUID(),
        name: String = "New Environment",
        variables: [EnvVariable] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.variables = variables
        self.isActive = isActive
    }

    // MARK: Backwards-compatible decode (missing projectId -> zero UUID)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = (try? c.decodeIfPresent(UUID.self, forKey: .projectId)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        variables = (try? c.decode([EnvVariable].self, forKey: .variables)) ?? []
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? false
    }

    static var empty: KoalaEnvironment { KoalaEnvironment() }

    /// Resolve a variable name, returning nil if not found or not enabled.
    func resolve(_ key: String) -> String? {
        variables.first(where: { $0.key == key && $0.isEnabled })?.value
    }
}
