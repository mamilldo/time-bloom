//
//  Configuration.swift
//  TimeBloom
//
//  All compile-time-stable configuration lives in one place so swapping
//  between staging and production (or someone else's Supabase project) is
//  a one-line change.
//
//  These values come from your TimeBloom Suite OpenAPI spec at
//  https://time-bloom-suite.lovable.app/openapi.json — they are public
//  endpoint identifiers, not secrets. The Supabase anon key is *designed*
//  to be embedded in clients (Row-Level Security on the database protects
//  the actual data), but the user's JWT — which we never hard-code — is
//  what gates read/write access to their rows.
//

import Foundation

enum Configuration {

    /// Root of the Supabase project. Used to build both the auth URL and
    /// the timer-api URL below.
    static let supabaseURL = URL(string: "https://cxgaxguhugxdbrrgqqcj.supabase.co")!

    /// Public anon key. Required as the `apikey` header on Supabase auth
    /// endpoints, and also accepted (in addition to the bearer token) on
    /// edge functions. Replace this string with the value from
    /// `Project Settings → API → anon public` in your Supabase dashboard.
    ///
    /// ⚠️  Treat this like a public identifier, *not* a secret. It only
    /// grants the access permitted by your RLS policies.
    static let supabaseAnonKey: String = "REPLACE_WITH_YOUR_SUPABASE_ANON_KEY"

    /// Endpoint for password / refresh-token grants.
    /// Docs: https://supabase.com/docs/reference/javascript/auth-signinwithpassword
    static var authTokenURL: URL {
        supabaseURL.appendingPathComponent("auth/v1/token")
    }

    /// Root of the Timer API edge function. All endpoints (status,
    /// projects, action POST) hang off this URL with query strings.
    static var timerAPIURL: URL {
        supabaseURL.appendingPathComponent("functions/v1/timer-api")
    }

    /// Keychain service identifier used by `KeychainStore`. Bundle-id
    /// keeps it unique per app install and easy to inspect via Keychain
    /// Access.app.
    static let keychainService = "app.timebloom.menubar"
}
