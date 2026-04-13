//
//  SupabaseAuthClient.swift
//  TimeBloom
//
//  Talks directly to Supabase's `/auth/v1/token` endpoint. This is a
//  separate client from `APIClient` because:
//
//  1. Auth requests must NOT have a bearer token attached — the only
//     credential is the public `apikey` header plus the password (or the
//     refresh token).
//  2. We want auth failures to fail fast instead of triggering the
//     refresh-and-retry loop that `APIClient` runs for every other call.
//
//  Both flows return a `SupabaseSession` so the caller can store both
//  tokens + the expiry uniformly.
//

import Foundation

actor SupabaseAuthClient {

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        // Supabase emits ISO-8601 with fractional seconds for `created_at`
        // etc. We don't actually decode any dates from the auth payload
        // (we keep `expires_in` as Int), but the decoder is configured
        // here for symmetry with `APIClient` should we add date fields.
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// Exchange an email + password for a `SupabaseSession`. Throws
    /// `APIError.unauthorized` on bad credentials.
    func login(email: String, password: String) async throws -> SupabaseSession {
        let body = SupabaseLoginRequest(email: email, password: password)
        return try await postToken(grantType: "password", body: body)
    }

    /// Use a refresh token to mint a new access token. Throws
    /// `APIError.unauthorized` if the refresh token has been revoked.
    func refresh(refreshToken: String) async throws -> SupabaseSession {
        let body = SupabaseRefreshRequest(refresh_token: refreshToken)
        return try await postToken(grantType: "refresh_token", body: body)
    }

    // MARK: - Private

    private func postToken<Body: Encodable>(grantType: String, body: Body) async throws -> SupabaseSession {
        // Build `…/auth/v1/token?grant_type=password` (or `refresh_token`).
        var components = URLComponents(url: Configuration.authTokenURL,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components.url else {
            throw APIError.transport(underlying: URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        // The Authorization header on auth endpoints is the anon key
        // again. Supabase requires both.
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decoding(underlying: error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(underlying: URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(SupabaseSession.self, from: data)
            } catch {
                throw APIError.decoding(underlying: error)
            }
        case 400, 401:
            // Supabase returns 400 for "Invalid login credentials" and
            // 401 for an expired refresh token. Treat both as unauthorized
            // so the UI can prompt for re-login.
            throw APIError.unauthorized
        default:
            // Try to surface the server's `{"error_description": "..."}`
            // or `{"msg": "..."}`. Either field is acceptable.
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap {
                ($0["error_description"] ?? $0["msg"]) as? String
            }
            throw APIError.server(status: http.statusCode, message: msg)
        }
    }
}
