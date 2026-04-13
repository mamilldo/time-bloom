//
//  APIError.swift
//  TimeBloom
//
//  One error type for everything our networking layer can throw. Views
//  can switch on the cases for tailored UI (e.g. show "Sign in again" for
//  `.unauthorized`), or just call `.userMessage` for a friendly string.
//

import Foundation

enum APIError: Error, LocalizedError {

    /// 401 from any endpoint. The auth layer uses this to trigger a
    /// refresh-token retry; if the retry also fails we surface it to the
    /// user as "session expired".
    case unauthorized

    /// 403 — typically "user has no organisation (not onboarded)".
    case forbidden(String?)

    /// 404 — for stop/switch when there's no running timer.
    case notFound(String?)

    /// 409 — start was attempted while a timer is already running.
    case conflict(String?)

    /// Catch-all for non-2xx with a parsed `{"error": "..."}` body.
    case server(status: Int, message: String?)

    /// JSON couldn't be parsed (likely a spec drift).
    case decoding(underlying: Error)

    /// URLSession-level issue: offline, DNS, TLS, timeout, etc.
    case transport(underlying: Error)

    /// Friendlier text for surfacing in alerts and toasts.
    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden(let msg):
            return msg ?? "You don't have permission to do that."
        case .notFound(let msg):
            return msg ?? "Nothing to do — no timer is running."
        case .conflict(let msg):
            return msg ?? "A timer is already running. Stop it first or switch."
        case .server(let status, let msg):
            return msg ?? "The server returned an error (HTTP \(status))."
        case .decoding:
            return "We couldn't read the server's response. The app may need an update."
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }

    var errorDescription: String? { userMessage }
}
