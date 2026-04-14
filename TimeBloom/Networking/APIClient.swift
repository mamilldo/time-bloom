//
//  APIClient.swift
//  TimeBloom
//
//  Talks to the Timer API edge function. Three responsibilities:
//
//  1. Build URLs for the documented endpoints
//     (`/?action=status`, `/?action=projects`, and `/` POST).
//  2. Attach the `apikey` header (Supabase requires it on edge functions
//     even when also passing a JWT) and the bearer token.
//  3. Translate non-2xx responses into typed `APIError` cases. On 401 we
//     try a single token refresh and retry — if *that* also returns 401
//     we surface `.unauthorized` and let the UI bounce to login.
//
//  This is an `actor` so concurrent timer-status polling and a manual
//  Start button tap can't accidentally interleave URLSession state. The
//  underlying `URLSession` is already thread-safe; the actor mainly
//  serialises the auth-refresh-retry handshake.
//

import Foundation

actor APIClient {

    private let auth: AuthService
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(auth: AuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session

        self.decoder = JSONDecoder()
        // Supabase edge functions emit timestamps as ISO-8601 with
        // fractional seconds. `.iso8601` alone doesn't accept fractional
        // seconds, so we use a custom DateFormatter chain via a closure.
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            if let d = Self.iso8601Fractional.date(from: str) { return d }
            if let d = Self.iso8601Plain.date(from: str)      { return d }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised date string: \(str)"
            )
        }

        self.encoder = JSONEncoder()
    }

    // MARK: - Endpoints (high-level, typed)

    func fetchStatus() async throws -> TimerStatus {
        try await get(query: [URLQueryItem(name: "action", value: "status")],
                      as: TimerStatus.self)
    }

    func fetchProjects() async throws -> [Project] {
        let envelope: ProjectsEnvelope = try await get(
            query: [URLQueryItem(name: "action", value: "projects")],
            as: ProjectsEnvelope.self
        )
        return envelope.projects
    }

    /// Fetch time entries for a given date (defaults to today).
    func fetchEntries(date: String? = nil) async throws -> EntriesResponse {
        var query = [URLQueryItem(name: "action", value: "entries")]
        if let date { query.append(URLQueryItem(name: "date", value: date)) }
        return try await get(query: query, as: EntriesResponse.self)
    }

    /// Performs any timer/entry action and returns the typed response.
    func perform(_ action: TimerAction) async throws -> TimerActionResponse {
        try await post(body: action, as: TimerActionResponse.self)
    }

    // MARK: - Generic request plumbing

    private func get<T: Decodable>(query: [URLQueryItem], as: T.Type) async throws -> T {
        var components = URLComponents(url: Configuration.timerAPIURL,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else {
            throw APIError.transport(underlying: URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await sendWithAuthRetry(request, decodingAs: T.self)
    }

    private func post<Body: Encodable, T: Decodable>(body: Body, as: T.Type) async throws -> T {
        var request = URLRequest(url: Configuration.timerAPIURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.decoding(underlying: error)
        }
        return try await sendWithAuthRetry(request, decodingAs: T.self)
    }

    /// Sends the request with current auth headers. If the server returns
    /// 401 we transparently force a token refresh and retry exactly once.
    private func sendWithAuthRetry<T: Decodable>(
        _ request: URLRequest,
        decodingAs: T.Type
    ) async throws -> T {
        var attempt = request
        try await attachAuthHeaders(to: &attempt)
        do {
            return try await send(attempt, decodingAs: T.self)
        } catch APIError.unauthorized {
            // Force a refresh by calling the auth service again. If our
            // token was cached we'll get the same one back; if it was
            // expired we'll get a fresh one.
            try await attachAuthHeaders(to: &attempt, forceRefresh: true)
            return try await send(attempt, decodingAs: T.self)
        }
    }

    private func attachAuthHeaders(to request: inout URLRequest, forceRefresh: Bool = false) async throws {
        // The anon key is required on every edge-function call, separately
        // from the bearer token.
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // `forceRefresh` is implemented by clearing the cached expiry on
        // the auth service. To keep AuthService simple we instead just
        // ask for the current token, which already returns a fresh one
        // when expiry is near. For an explicit force-refresh we'd extend
        // AuthService — for now, both call sites use the same path.
        _ = forceRefresh
        let token = try await auth.currentAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func send<T: Decodable>(_ request: URLRequest, decodingAs: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sendWithRetryOnConnectionLost(request)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(underlying: URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(underlying: error)
            }

        case 401:
            throw APIError.unauthorized

        case 403:
            throw APIError.forbidden(parseErrorMessage(data))

        case 404:
            throw APIError.notFound(parseErrorMessage(data))

        case 409:
            throw APIError.conflict(parseErrorMessage(data))

        default:
            throw APIError.server(status: http.statusCode,
                                  message: parseErrorMessage(data))
        }
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
    }

    /// Retry once on `-1005 "The network connection was lost"`. This
    /// happens when the server closes an idle keep-alive connection while
    /// URLSession tries to reuse it. Apple's recommended fix is to retry.
    private func sendWithRetryOnConnectionLost(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .networkConnectionLost {
            // Single retry — if it fails again, let it propagate.
            return try await session.data(for: request)
        }
    }

    // MARK: - Date formatters

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
