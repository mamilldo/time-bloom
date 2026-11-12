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
import OSLog
import Security

private let log = Logger(subsystem: Configuration.keychainService, category: "keychain")

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

        // Update in place first. The old "delete, then add" approach broke
        // silently when the delete was refused (e.g. the item was created
        // by an earlier build with a different code signature): the add
        // then failed with errSecDuplicateItem and the OLD refresh token
        // stayed in the Keychain. Supabase rotates refresh tokens, so on
        // the next launch that stale token was rejected and the user had
        // to sign in again.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary,
                                         attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus != errSecItemNotFound {
            // Something is wrong with the existing item (typically an ACL
            // that doesn't trust this build). Remove it and start over.
            log.error("Keychain update of \(key.rawValue, privacy: .public) failed: \(updateStatus) – recreating item")
            SecItemDelete(baseQuery(for: key) as CFDictionary)
        }

        var addQuery = baseQuery(for: key)
        addQuery[kSecValueData as String] = data
        // `.afterFirstUnlock` lets background helpers read the token after
        // the user has logged in once per boot — the right tradeoff for a
        // background-y menu bar app.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Keychain add of \(key.rawValue, privacy: .public) failed: \(status)")
            throw KeychainError.unhandled(status)
        }
    }

    func get(_ key: KeychainKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String]  = true
        query[kSecMatchLimit as String]  = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            // Most often errSecAuthFailed / errSecInteractionNotAllowed:
            // the item exists but this build of the app isn't allowed to
            // read it (code signature changed). Shows up in Console.app.
            log.error("Keychain read of \(key.rawValue, privacy: .public) failed: \(status)")
        }
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
