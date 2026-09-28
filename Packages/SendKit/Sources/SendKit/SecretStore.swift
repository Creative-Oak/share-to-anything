import Foundation
import Security

/// Secrets (passwords, tokens, API keys) in the Keychain, synced across devices via iCloud Keychain.
public struct SecretStore: Sendable {
    public static let shared = SecretStore(accessGroup: AppConfig.keychainAccessGroup)

    let service = "dk.creativeoak.ShareToAnything"
    let accessGroup: String?

    public init(accessGroup: String?) { self.accessGroup = accessGroup }

    private func baseQuery(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value`, or deletes the item when `value` is nil or empty.
    public func set(_ value: String?, for key: String) {
        var deleteQuery = baseQuery(key)
        deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(deleteQuery as CFDictionary)

        guard let value, !value.isEmpty else { return }
        var addQuery = baseQuery(key)
        addQuery[kSecAttrSynchronizable as String] = true
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("ShareToAnything: Keychain write for %@ failed (%d)", key, status)
        }
    }
}
