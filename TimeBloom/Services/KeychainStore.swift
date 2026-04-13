//
//  KeychainStore.swift
//  TimeBloom
//
//  A tiny wrapper around Apple's Security framework. We use the Keychain
//  for two values: the access token and the refresh token. Both expire,
//  but they're sensitive while valid (anyone holding them can act as the
//  user against the API), so they MUST NOT live in UserDefaults.
//
//  This file uses the lower-level `SecItem` C APIs because they're the
//  only Keychain APIs that work in a sandboxed macOS app without extra
//  iCloud entitlements. The functions are synchronous and fast — Keychain
//  reads/writes return in microseconds so calling them on the main actor
//  is fine.
//

import Foundation
import Security

/// Logical names for the two values we store. Using an enum avoids typos
/// and keeps the storage layout discoverable.
enum KeychainKey: String {
    case accessToken
    case refreshToken
}

struct KeychainStore {

    /// Service string written into every Keychain query. The combination
    /// of (service, account) uniquely identifies an item.
    let service: String

    init(service: String = Configuration.keychainService) {
        self.service = service
    }

    // MARK: - Public API

    func set(_ value: String, for key: KeychainKey) throws {
        let data = Data(value.utf8)

        // Always delete first so we never have to deal with the duplicate-
        // item branch of `SecItemAdd`. Cheaper to write than to maintain
        // an "update if exists, otherwise add" code path.
        let deleteQuery = baseQuery(for: key)
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = baseQuery(for: key)
        addQuery[kSecValueData as String] = data
        // `.afterFirstUnlock` lets background helpers read the token after
        // the user has logged in once per boot — the right tradeoff for a
        // background-y menu bar app.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    func get(_ key: KeychainKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String]  = true
        query[kSecMatchLimit as String]  = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str  = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    func delete(_ key: KeychainKey) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Convenience used at logout to wipe everything we own.
    func deleteAll() {
        delete(.accessToken)
        delete(.refreshToken)
    }

    // MARK: - Internals

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key.rawValue,
        ]
    }
}

enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain error \(status): \(msg)"
        }
    }
}
