import Foundation
import Security
import os

/// Provides simple CRUD operations for storing secrets in the macOS Keychain.
/// Uses generic password items scoped to the app's bundle identifier.
enum KeychainHelper {

    private static let service = Bundle.main.bundleIdentifier ?? "com.mikefullerton.Whippet"

    /// Stores a value in the Keychain for the given account key.
    /// Overwrites any existing value for the same key.
    static func set(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)
        // Delete any existing item first
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Log.settings.error("Keychain set failed for '\(key, privacy: .public)': \(status)")
        }
        return status == errSecSuccess
    }

    /// Retrieves a value from the Keychain for the given account key.
    /// Returns nil if no item exists or an error occurs.
    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Log.settings.error("Keychain get failed for '\(key, privacy: .public)': \(status)")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes the Keychain item for the given account key.
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns whether a value exists in the Keychain for the given key.
    static func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
