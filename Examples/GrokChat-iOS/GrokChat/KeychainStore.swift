//
//  KeychainStore.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import Security

/// A minimal Keychain wrapper that stores strings as generic passwords.
enum KeychainStore {
    /// The Keychain service that GrokChat's items belong to.
    static let service = "io.marcodotio.GrokChat"

    /// An error that a Keychain operation returns.
    struct Failure: LocalizedError {
        var status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "The Keychain operation failed (\(status))."
        }
    }

    /// Returns the string stored for an account, or `nil` if there isn't one.
    static func string(forAccount account: String) -> String? {
        var query = baseQuery(forAccount: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores a string for an account, replacing any existing value.
    static func set(_ value: String, forAccount account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(forAccount: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            try check(status)
            return
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        try check(SecItemAdd(item as CFDictionary, nil))
    }

    /// Removes the string stored for an account, if there is one.
    static func removeValue(forAccount account: String) throws {
        let status = SecItemDelete(baseQuery(forAccount: account) as CFDictionary)
        guard status != errSecItemNotFound else { return }
        try check(status)
    }

    private static func baseQuery(forAccount account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
