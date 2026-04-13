//
//  Models.swift
//  TimeBloom
//
//  Codable types that mirror the API. They are intentionally permissive
//  (most string fields are optional) so a slightly different real-world
//  payload doesn't crash the decoder. Adjust to the canonical schema once
//  you've audited the live API at /api-docs.
//

import Foundation

// MARK: - Auth

/// Body we POST to `/auth/login`.
struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// Server response for a successful login. The exact key for the token may
/// be `token`, `access_token`, or `accessToken` depending on the framework
/// powering the API; we use a custom decoder to accept any of them so this
/// model survives small spec changes.
struct LoginResponse: Decodable {
    let token: String
    let user: User?

    private enum CodingKeys: String, CodingKey {
        case token, access_token, accessToken, user
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(String.self, forKey: .token) {
            self.token = t
        } else if let t = try c.decodeIfPresent(String.self, forKey: .access_token) {
            self.token = t
        } else if let t = try c.decodeIfPresent(String.self, forKey: .accessToken) {
            self.token = t
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .token, in: c,
                debugDescription: "No token field in login response"
            )
        }
        self.user = try c.decodeIfPresent(User.self, forKey: .user)
    }
}

// MARK: - Domain types

struct User: Codable, Identifiable, Hashable {
    let id: String
    let email: String?
    let name: String?
}

struct Project: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Optional accent the API may return for project-coloured chips.
    let color: String?
}

struct TaskItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Some APIs scope tasks to a project. If yours doesn't, leave nil and
    /// the picker will show a flat list.
    let projectId: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case projectId = "project_id"
    }
}

/// A single timer entry. The API may use ISO-8601 strings; `APIClient`
/// configures a date decoding strategy that handles both forms.
struct TimeEntry: Codable, Identifiable, Hashable {
    let id: String
    let taskId: String?
    let projectId: String?
    let startedAt: Date
    let stoppedAt: Date?
    let notes: String?

    var isRunning: Bool { stoppedAt == nil }

    /// Wall-clock seconds since the entry started. Re-evaluated on every
    /// access — call inside a `Timer` tick to get a live duration.
    func elapsed(now: Date = .now) -> TimeInterval {
        (stoppedAt ?? now).timeIntervalSince(startedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, notes
        case taskId = "task_id"
        case projectId = "project_id"
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
    }
}

// MARK: - Request bodies

struct StartTimerRequest: Encodable {
    let taskId: String?
    let projectId: String?
    let startedAt: Date
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case notes
        case taskId = "task_id"
        case projectId = "project_id"
        case startedAt = "started_at"
    }
}

struct UpdateTimerRequest: Encodable {
    var startedAt: Date?
    var stoppedAt: Date?
    var notes: String?
    var taskId: String?

    private enum CodingKeys: String, CodingKey {
        case notes
        case taskId = "task_id"
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
    }
}
