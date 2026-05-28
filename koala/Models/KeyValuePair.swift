import Foundation

struct KeyValuePair: Identifiable, Codable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var description: String
    var isEnabled: Bool
    var isSecret: Bool
    /// When true, `value` is stored in the macOS Keychain (via `VaultService`)
    /// rather than on disk. Custom encode/decode below ensures the plaintext
    /// never lands in JSON files or collaboration bundles.
    var isVault: Bool

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        description: String = "",
        isEnabled: Bool = true,
        isSecret: Bool = false,
        isVault: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.description = description
        self.isEnabled = isEnabled
        self.isSecret = isSecret
        self.isVault = isVault
    }

    static var empty: KeyValuePair {
        KeyValuePair()
    }

    // MARK: Codable (BC + vault stripping)

    private enum CodingKeys: String, CodingKey {
        case id, key, value, description, isEnabled, isSecret, isVault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        isSecret = (try? c.decode(Bool.self, forKey: .isSecret)) ?? false
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
        try c.encode(description, forKey: .description)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(isSecret, forKey: .isSecret)
        try c.encode(isVault, forKey: .isVault)
    }
}
