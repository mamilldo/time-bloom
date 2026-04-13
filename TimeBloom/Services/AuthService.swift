//
//  AuthService.swift
//  TimeBloom
//
//  Single source of truth for "are we signed in?" and "what's the current
//  bearer token?". Wraps `KeychainStore` (persistence) and
//  `SupabaseAuthClient` (network) and exposes high-level operations:
//
//      try await auth.signIn(email:, password:)
//      try await auth.currentAccessToken()   // refreshes if expired
//      auth.signOut()
//
//  Marked `@Observable` so SwiftUI views can react to sign-in / sign-out
//  without manual notification plumbing.
//

import Foundation
import Observation

@MainActor
@Observable
final class AuthService {

    // MARK: - Observable state

    /// `true` whenever we have a non-nil access token in memory. Drives
    /// the login-vs-main switch in `PopoverRootView`.
    private(set) var isSignedIn: Bool = false

    /// The user record returned by Supabase at login. Optional because
    /// older session restores from Keychain don't include it.
    private(set) var currentUser: SupabaseUser?

    // MARK: - Private state

    private let keychain: KeychainStore
    private let supabase: SupabaseAuthClient

    /// Cached in-memory copies of what's in Keychain. We keep them around
    /// so we don't hit the Keychain on every API call (it's fast but not
    /// free, and reading on the main actor would block UI updates if a
    /// Smart Card prompt ever appeared).
    private var accessToken: String?
    private var refreshToken: String?
    private var accessTokenExpiry: Date?

    /// Serialises concurrent refresh attempts. If two API calls expire at
    /// the same time they should share one network request, not race.
    private var inFlightRefresh: Task<String, Error>?

    init(
        keychain: KeychainStore = KeychainStore(),
        supabase: SupabaseAuthClient = SupabaseAuthClient()
    ) {
        self.keychain = keychain
        self.supabase = supabase
        restoreFromKeychain()
    }

    // MARK: - Sign-in / sign-out

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.login(email: email, password: password)
        try persist(session)
    }

    func signOut() {
        accessToken        = nil
        refreshToken       = nil
        accessTokenExpiry  = nil
        currentUser        = nil
        isSignedIn         = false
        keychain.deleteAll()
    }

    // MARK: - Token access

    /// Returns a valid access token, refreshing it transparently if it
    /// is within 30 seconds of expiring. Throws `APIError.unauthorized`
    /// if there is no usable token AND no refresh token.
    func currentAccessToken() async throws -> String {
        if let token = accessToken,
           let expiry = accessTokenExpiry,
           expiry.timeIntervalSinceNow > 30 {
            return token
        }
        return try await performRefresh()
    }

    /// Synchronous accessor used by the AppDelegate to decide whether to
    /// kick off background refreshes at launch. Doesn't validate expiry
    /// — `currentAccessToken()` is the source of truth for that.
    var hasStoredCredentials: Bool {
        accessToken != nil && refreshToken != nil
    }

    // MARK: - Private plumbing

    private func performRefresh() async throws -> String {
        // Coalesce concurrent callers onto the same in-flight Task so we
        // only hit Supabase once even if 5 API calls expire at once.
        if let existing = inFlightRefresh {
            return try await existing.value
        }

        guard let refreshToken else {
            throw APIError.unauthorized
        }

        // `Task { ... }` inherits the enclosing actor (MainActor),
        // so `self.persist` runs on MainActor automatically after the
        // `await` hop into `supabase`.
        let task = Task<String, Error> { @MainActor in
            let session = try await self.supabase.refresh(refreshToken: refreshToken)
            try self.persist(session)
            return session.accessToken
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }

        do {
            return try await task.value
        } catch {
            // Refresh tokens have a long but finite lifetime; if Supabase
            // says no, we're done. Wipe and force re-login.
            if case APIError.unauthorized = error {
                signOut()
            }
            throw error
        }
    }

    private func persist(_ session: SupabaseSession) throws {
        accessToken       = session.accessToken
        refreshToken      = session.refreshToken
        accessTokenExpiry = session.expiry
        currentUser       = session.user
        isSignedIn        = true

        try keychain.set(session.accessToken,  for: .accessToken)
        try keychain.set(session.refreshToken, for: .refreshToken)
    }

    private func restoreFromKeychain() {
        let access  = keychain.get(.accessToken)
        let refresh = keychain.get(.refreshToken)
        accessToken  = access
        refreshToken = refresh
        // We don't know the expiry — assume "expired" so the first API
        // call triggers a refresh. That's the safest default.
        accessTokenExpiry = nil
        isSignedIn = (access != nil) && (refresh != nil)
    }
}
