import Foundation
import Observation

// MARK: - VaultService
//
// Per-project secret variable storage backed by the macOS Keychain.
//
// Vault entries are referenced from `EnvVariable` / `KeyValuePair` rows with
// `isVault == true`. The plaintext value is NEVER written to JSON on disk and
// is NEVER included in collaboration bundles. The Keychain item is keyed by
// `vault.{projectId}.{varName}`. The set of names per project is tracked in
// UserDefaults so the UI can enumerate vault entries without scanning the
// Keychain directly.

@MainActor
@Observable
final class VaultService {

    // MARK: Dependencies

    private let keychain: KeychainService
    private let defaults: UserDefaults

    // MARK: Init

    init(keychain: KeychainService = .shared, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Persists `value` to the Keychain under `vault.{projectId}.{name}` and
    /// records `name` in the per-project index in UserDefaults.
    func set(_ name: String, value: String, projectId: UUID) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try keychain.set(value, for: keychainKey(name: trimmed, projectId: projectId))
        addToIndex(name: trimmed, projectId: projectId)
        bumpRevision()
    }

    /// Reads the secret value from the Keychain. Returns nil if absent or
    /// if Keychain access fails.
    ///
    /// `nonisolated` so it can be called from `VariableResolver` (a non-actor
    /// enum). The underlying `KeychainService` is thread-safe and this method
    /// touches no observable state.
    nonisolated func get(_ name: String, projectId: UUID) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return (try? keychain.string(for: keychainKey(name: trimmed, projectId: projectId))) ?? nil
    }

    /// Removes the secret from Keychain and from the per-project index.
    func delete(_ name: String, projectId: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? keychain.delete(keychainKey(name: trimmed, projectId: projectId))
        removeFromIndex(name: trimmed, projectId: projectId)
        bumpRevision()
    }

    /// All vault variable names for a project (alphabetical).
    func allNames(projectId: UUID) -> [String] {
        loadIndex(projectId: projectId).sorted()
    }

    /// Bumped on every mutation so SwiftUI views observing this service via
    /// `@Bindable` / `@Environment` re-render when a vault entry changes.
    private(set) var revision: Int = 0

    // MARK: - Private

    private func bumpRevision() {
        revision &+= 1
    }

    nonisolated private func keychainKey(name: String, projectId: UUID) -> String {
        "vault.\(projectId.uuidString).\(name)"
    }

    private func indexKey(projectId: UUID) -> String {
        "koala.vault.index.\(projectId.uuidString)"
    }

    private func loadIndex(projectId: UUID) -> Set<String> {
        let arr = defaults.array(forKey: indexKey(projectId: projectId)) as? [String] ?? []
        return Set(arr)
    }

    private func saveIndex(_ index: Set<String>, projectId: UUID) {
        defaults.set(Array(index), forKey: indexKey(projectId: projectId))
    }

    private func addToIndex(name: String, projectId: UUID) {
        var index = loadIndex(projectId: projectId)
        index.insert(name)
        saveIndex(index, projectId: projectId)
    }

    private func removeFromIndex(name: String, projectId: UUID) {
        var index = loadIndex(projectId: projectId)
        index.remove(name)
        saveIndex(index, projectId: projectId)
    }
}

// MARK: - SwiftUI environment plumbing

import SwiftUI

private struct VaultServiceKey: EnvironmentKey {
    static let defaultValue: VaultService? = nil
}

private struct VaultProjectIdKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// Inject the app-wide `VaultService` so leaf views (e.g. the row editor)
    /// can read/write Keychain values without prop-drilling.
    var vaultService: VaultService? {
        get { self[VaultServiceKey.self] }
        set { self[VaultServiceKey.self] = newValue }
    }

    /// The active project ID for scoping vault lookups in the current view tree.
    var vaultProjectId: UUID? {
        get { self[VaultProjectIdKey.self] }
        set { self[VaultProjectIdKey.self] = newValue }
    }
}
