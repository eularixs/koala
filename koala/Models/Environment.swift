import Foundation

// MARK: - EnvVariable

struct EnvVariable: Identifiable, Codable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var isEnabled: Bool
    /// When true, `value` is stored in the macOS Keychain (via `VaultService`)
    /// rather than on disk. Custom encode/decode below ensures the plaintext
    /// never lands in JSON files or collaboration bundles.
    var isVault: Bool

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isSecret: Bool = false,
        isEnabled: Bool = true,
        isVault: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
        self.isVault = isVault
    }

    static var empty: EnvVariable { EnvVariable() }

    // MARK: Codable (BC + vault stripping)

    private enum CodingKeys: String, CodingKey {
        case id, key, value, isSecret, isEnabled, isVault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        isSecret = (try? c.decode(Bool.self, forKey: .isSecret)) ?? false
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        isVault = (try? c.decode(Bool.self, forKey: .isVault)) ?? false
        // Vault values are never persisted — clear any stale plaintext that
        // might have leaked into an older JSON file.
        if isVault { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(key, forKey: .key)
        // CRITICAL: when isVault is true, emit empty string instead of the
        // in-memory plaintext. The real value lives in the Keychain.
        try c.encode(isVault ? "" : value, forKey: .value)
        try c.encode(isSecret, forKey: .isSecret)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(isVault, forKey: .isVault)
    }
}

// MARK: - KoalaEnvironment

/// Named `KoalaEnvironment` to avoid collision with SwiftUI's `Environment` property wrapper.
struct KoalaEnvironment: Identifiable, Codable, Hashable {
    var id: UUID
    var projectId: UUID
    var name: String
    var color: String?
    var variables: [EnvVariable]
    var isActive: Bool

    init(
        id: UUID = UUID(),
        projectId: UUID = UUID(),
        name: String = "New Environment",
        color: String? = nil,
        variables: [EnvVariable] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.color = color
        self.variables = variables
        self.isActive = isActive
    }

    // MARK: Backwards-compatible decode (missing projectId/color -> defaults)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = (try? c.decodeIfPresent(UUID.self, forKey: .projectId)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        variables = (try? c.decode([EnvVariable].self, forKey: .variables)) ?? []
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? false
    }

    static var empty: KoalaEnvironment { KoalaEnvironment() }

    /// Resolve a variable name, returning nil if not found or not enabled.
    /// Vault-backed variables intentionally resolve to `nil` here — callers
    /// that need a vault value must go through `VariableResolver` with a
    /// `VaultService` instance (only at request SEND time).
    func resolve(_ key: String) -> String? {
        guard let v = variables.first(where: { $0.key == key && $0.isEnabled }) else { return nil }
        if v.isVault { return nil }
        return v.value
    }
}
