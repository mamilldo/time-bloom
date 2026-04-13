//
//  Models.swift
//  TimeBloom
//
//  Codable types that mirror the Timer API exactly as documented at
//  https://time-bloom-suite.lovable.app/openapi.json
//
//  The API is intentionally narrow: a single status query, a single
//  projects-with-tasks query, and a single POST endpoint that performs
//  start / stop / switch via an `action` discriminator. Mirroring it
//  literally keeps the networking layer dumb and the SwiftUI layer
//  predictable.
//

import Foundation

// MARK: - Auth (Supabase /auth/v1/token)
//
// Supabase's password-grant endpoint expects a JSON body with `email` and
// `password`, and returns the bundle below. We only need `access_token`,
// `refresh_token`, and `expires_at` for runtime use; the rest is decoded
// for completeness but ignored.

struct SupabaseLoginRequest: Encodable {
    let email: String
    let password: String
}

struct SupabaseRefreshRequest: Encodable {
    let refresh_token: String
}

struct SupabaseSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int           // seconds from now
    let expiresAt: Int?          // unix timestamp (older Supabase builds omit this)
    let tokenType: String
    let user: SupabaseUser?

    private enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case expiresAt    = "expires_at"
        case tokenType    = "token_type"
        case user
    }

    /// The wall-clock instant this token stops being valid. We trust
    /// `expires_at` when present (server clock) and otherwise extrapolate
    /// from `expires_in` against the local clock.
    var expiry: Date {
        if let expiresAt { return Date(timeIntervalSince1970: TimeInterval(expiresAt)) }
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

struct SupabaseUser: Decodable, Hashable {
    let id: String
    let email: String?
}

// MARK: - Timer API: status

/// `GET /?action=status` returns one of these two shapes. Supabase's
/// OpenAPI uses an unkeyed `oneOf` discriminated solely by the `running`
/// boolean, so we decode by peeking at that field first.
enum TimerStatus: Decodable, Equatable {
    case running(RunningTimer)
    case stopped

    private enum CodingKeys: String, CodingKey { case running }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let isRunning = try c.decode(Bool.self, forKey: .running)
        if isRunning {
            self = .running(try RunningTimer(from: decoder))
        } else {
            self = .stopped
        }
    }

    var runningTimer: RunningTimer? {
        if case .running(let t) = self { return t }
        return nil
    }
}

/// The richer payload returned when a timer is running.
struct RunningTimer: Decodable, Equatable {
    let timerId: String
    let projectId: String
    let project: String                 // human-readable project name
    let taskId: String?
    let task: String?                   // human-readable task name (nil if no task)
    let startTime: Date
    let elapsedSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case timerId        = "timer_id"
        case projectId      = "project_id"
        case project
        case taskId         = "task_id"
        case task
        case startTime      = "start_time"
        case elapsedSeconds = "elapsed_seconds"
    }
}

// MARK: - Timer API: projects

/// `GET /?action=projects` wraps the list in a `{ "projects": [...] }`
/// envelope, which we collapse to the inner array at the API-client layer.
struct ProjectsEnvelope: Decodable {
    let projects: [Project]
}

struct Project: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let client: String
    let tasks: [TaskItem]
}

/// Tasks are nested under their project — the API has no flat /tasks list.
/// `TaskItem` (vs. `Task`) avoids the name collision with Swift Concurrency's
/// `_Concurrency.Task`.
struct TaskItem: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - Timer API: action POST bodies

/// All three action requests POST to the same `/` endpoint. Encoding them
/// as a single enum lets the call site stay terse: `api.perform(.start(...))`.
enum TimerAction: Encodable {
    case start(projectId: String, taskId: String?)
    case stop
    case switchTo(projectId: String, taskId: String?)

    private enum CodingKeys: String, CodingKey {
        case action, project_id, task_id
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let projectId, let taskId):
            try c.encode("start", forKey: .action)
            try c.encode(projectId, forKey: .project_id)
            try c.encodeIfPresent(taskId, forKey: .task_id)
        case .stop:
            try c.encode("stop", forKey: .action)
        case .switchTo(let projectId, let taskId):
            try c.encode("switch", forKey: .action)
            try c.encode(projectId, forKey: .project_id)
            try c.encodeIfPresent(taskId, forKey: .task_id)
        }
    }
}

// MARK: - Timer API: action responses
//
// The OpenAPI spec describes four distinct response shapes across the
// three actions. We model them as one enum and decode by peeking at the
// `action` field (for switch) and presence of `logged_minutes` (for stop).

enum TimerActionResponse: Decodable {
    case started(timerId: String)
    case stopped(loggedMinutes: Int, project: String)
    case switchedReassigned                              // < 60s — same entry, new project/task
    case switchedNew(loggedMinutes: Int, newTimerId: String)

    private enum CodingKeys: String, CodingKey {
        case ok, action, timer_id, logged_minutes, project, new_timer_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Switch responses include an `action` field; start/stop don't.
        if let action = try c.decodeIfPresent(String.self, forKey: .action) {
            switch action {
            case "reassigned":
                self = .switchedReassigned
            case "switched":
                let mins = try c.decode(Int.self, forKey: .logged_minutes)
                let id   = try c.decode(String.self, forKey: .new_timer_id)
                self = .switchedNew(loggedMinutes: mins, newTimerId: id)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .action, in: c,
                    debugDescription: "Unknown switch action: \(action)"
                )
            }
            return
        }

        // No `action` field: it's either start (has `timer_id`) or stop
        // (has `logged_minutes`).
        if let id = try c.decodeIfPresent(String.self, forKey: .timer_id) {
            self = .started(timerId: id)
        } else if let mins = try c.decodeIfPresent(Int.self, forKey: .logged_minutes) {
            let project = try c.decode(String.self, forKey: .project)
            self = .stopped(loggedMinutes: mins, project: project)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .ok, in: c,
                debugDescription: "Unrecognised action response shape"
            )
        }
    }
}

// MARK: - Errors surfaced by the API

/// `{ "error": "A timer is already running. Stop it first." }`
struct APIErrorBody: Decodable {
    let error: String
}
