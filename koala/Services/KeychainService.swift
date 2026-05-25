import Foundation
import Security

// MARK: - Error

enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            return "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
        case .decodingFailed:
            return "Failed to decode keychain value as UTF-8 string."
        }
    }
}

// MARK: - Service

/// Thin Security-framework wrapper for generic-password items.
/// All items are stored under the service identifier `"com.koala.keychain"`.
final class KeychainService {

    static let shared = KeychainService()

    private let service = "com.koala.keychain"

    init() {}

    // MARK: Write

    func set(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unhandled(updateStatus) }
        } else if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        } else {
            throw KeychainError.unhandled(status)
        }
    }

    func set(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else { throw KeychainError.decodingFailed }
        try set(data, for: key)
    }

    // MARK: Read

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        return result as? Data
    }

    func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.decodingFailed }
        return string
    }

    // MARK: Delete

    func delete(_ key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: Private

    private func baseQuery(for key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
    }
}
