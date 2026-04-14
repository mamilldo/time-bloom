//
//  TimerStore.swift
//  TimeBloom
//
//  The brain of the app. Owns the canonical "is a timer running and what
//  is it" state, drives the periodic poll that keeps us in sync with the
//  web app, and decides when to surface the long-running-timer warning.
//
//  All UI reads from this single `@Observable` instance — there's no
//  duplication of timer state in views.
//

import Foundation
import Observation

@MainActor
@Observable
final class TimerStore {

    // MARK: - Observable state read by SwiftUI

    /// Latest timer state from the server. `nil` means "we haven't asked
    /// yet" (UI shows a spinner). `.stopped` means we asked and there's
    /// no running timer.
    private(set) var status: TimerStatus?

    /// Cached project list for the picker. Refreshed on every popover
    /// open so a project added on the web shows up immediately.
    private(set) var projects: [Project] = []

    /// Today's time entries, shown in the Harvest-style list.
    private(set) var entries: [TimeEntry] = []

    /// Total minutes logged today (sum of all entries).
    var todayTotalMinutes: Int {
        entries.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Most-recent error surfaced by an action call. The view shows it
    /// as an inline banner; clearing it is the view's responsibility.
    var lastError: APIError?

    /// Set to `true` while a request is in-flight so buttons can disable
    /// themselves and we can show a small progress indicator.
    private(set) var isBusy: Bool = false

    // MARK: - Wall-clock tick
    //
    // `RunningTimer.elapsedSeconds` is a snapshot from the moment the
    // server replied. We need a smooth ticking display, so we publish a
    // `now` stamp every second. Views compute live elapsed as
    // `now.timeIntervalSince(timer.startTime)`.

    private(set) var now: Date = .now
    private var tickTask: Task<Void, Never>?

    // MARK: - Background polling

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 30

    // MARK: - Long-running guard
    //
    // We post the long-running notification at most once per timer (i.e.
    // per `timer_id`) to avoid spamming the user every minute past 4h.

    private var longRunningWarningPostedFor: String?

    // MARK: - Dependencies

    private let api: APIClient
    private let auth: AuthService
    private let settings: AppSettings
    private let notifications: NotificationManager

    init(
        api: APIClient,
        auth: AuthService,
        settings: AppSettings,
        notifications: NotificationManager
    ) {
        self.api = api
        self.auth = auth
        self.settings = settings
        self.notifications = notifications
    }

    // MARK: - Lifecycle

    /// Begin the 1-second wall-clock tick AND the 30-second server poll.
    /// Safe to call multiple times — second call is a no-op.
    func startBackgroundLoops() {
        if tickTask == nil {
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        guard let self else { return }
                        self.now = .now
                        self.checkLongRunningWarning()
                    }
                }
            }
        }
        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 30))
                }
            }
        }
    }

    func stopBackgroundLoops() {
        tickTask?.cancel();    tickTask = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    // MARK: - Server reads

    /// Pull the latest status from the server. Used by the polling loop
    /// AND by views that want a forced refresh (e.g. on popover open).
    func refresh() async {
        guard auth.isSignedIn else { return }
        do {
            let s = try await api.fetchStatus()
            self.status = s
            // Reset the long-running guard if the running timer changed.
            if case .running(let t) = s, longRunningWarningPostedFor != t.timerId {
                longRunningWarningPostedFor = nil
            }
        } catch APIError.unauthorized {
            // The auth service has already wiped credentials. The view
            // tree will switch to the login screen automatically because
            // it observes `auth.isSignedIn`.
            self.status = nil
        } catch let error as APIError {
            self.lastError = error
        } catch {
            self.lastError = .transport(underlying: error)
        }
    }

    /// Refresh the cached projects list.
    func refreshProjects() async {
        guard auth.isSignedIn else { return }
        do {
            self.projects = try await api.fetchProjects()
        } catch let error as APIError {
            self.lastError = error
        } catch { /* ignore transport errors on background refresh */ }
    }

    /// Fetch today's time entries from the server.
    func refreshEntries() async {
        guard auth.isSignedIn else { return }
        do {
            let response = try await api.fetchEntries()
            self.entries = response.entries
        } catch let error as APIError {
            self.lastError = error
        } catch { /* ignore transport errors */ }
    }

    // MARK: - Timer actions

    func start(projectId: String, taskId: String?) async {
        await runAction { [api] in try await api.perform(.start(projectId: projectId, taskId: taskId)) }
    }

    func stop() async {
        await runAction { [api] in try await api.perform(.stop) }
    }

    func switchTo(projectId: String, taskId: String?) async {
        await runAction { [api] in try await api.perform(.switchTo(projectId: projectId, taskId: taskId)) }
    }

    // MARK: - Entry CRUD

    func createEntry(projectId: String, taskId: String?, startTime: Date, endTime: Date, description: String?) async {
        await runAction { [api] in
            try await api.perform(.create(projectId: projectId, taskId: taskId,
                                          startTime: startTime, endTime: endTime,
                                          description: description))
        }
    }

    func editEntry(timerId: String, projectId: String?, taskId: String?,
                   startTime: Date?, endTime: Date?, description: String?) async {
        await runAction { [api] in
            try await api.perform(.edit(timerId: timerId, projectId: projectId,
                                        taskId: taskId, startTime: startTime,
                                        endTime: endTime, description: description))
        }
    }

    func deleteEntry(timerId: String) async {
        await runAction { [api] in
            try await api.perform(.delete(timerId: timerId))
        }
    }

    /// Common wrapper: sets `isBusy`, runs the action, refreshes status
    /// + entries, and converts errors into `lastError`.
    private func runAction(_ body: @escaping () async throws -> TimerActionResponse) async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await body()
            await refresh()
            await refreshEntries()
        } catch let error as APIError {
            self.lastError = error
        } catch {
            self.lastError = .transport(underlying: error)
        }
    }

    // MARK: - Long-running detection

    private func checkLongRunningWarning() {
        guard case .running(let timer) = status else { return }
        let thresholdSeconds = settings.longRunningTimerHours * 3600
        let liveElapsed = Int(now.timeIntervalSince(timer.startTime))
        guard liveElapsed >= thresholdSeconds else { return }
        guard longRunningWarningPostedFor != timer.timerId else { return }
        longRunningWarningPostedFor = timer.timerId

        Task { [notifications] in
            await notifications.postLongRunningTimer(
                project: timer.project,
                hours: settings.longRunningTimerHours
            )
        }
    }

    // MARK: - Idle handling
    //
    // Called by `IdleMonitor` when the user crosses the idle threshold
    // while a timer is running. The actual UI is presented by
    // `MenuBarController` using `pendingIdleEvent`; we just publish.

    private(set) var pendingIdleEvent: IdleEvent?

    func handleIdleDetected(seconds: TimeInterval) {
        guard case .running(let timer) = status else { return }
        pendingIdleEvent = IdleEvent(
            idleSeconds: seconds,
            timer: timer,
            detectedAt: .now
        )
        Task { [notifications] in
            await notifications.postIdleDetected(
                project: timer.project,
                idleMinutes: Int(seconds / 60)
            )
        }
    }

    /// Called by the idle dialog when the user picks an option.
    func resolveIdle(_ resolution: IdleResolution) async {
        defer { pendingIdleEvent = nil }
        switch resolution {
        case .keep:
            break
        case .stop:
            await stop()
        case .switchTo(let projectId, let taskId):
            await switchTo(projectId: projectId, taskId: taskId)
        case .addAsNewEntry(let projectId, let taskId, let startTime, let endTime):
            // Stop the running timer first, then create a manual entry
            // for the idle period on the selected task.
            await stop()
            await createEntry(projectId: projectId, taskId: taskId,
                            startTime: startTime, endTime: endTime,
                            description: nil)
        }
    }
}

struct IdleEvent: Equatable {
    let idleSeconds: TimeInterval
    let timer: RunningTimer
    let detectedAt: Date

    /// Approximate start of the idle period.
    var idleStartedAt: Date {
        detectedAt.addingTimeInterval(-idleSeconds)
    }
}

enum IdleResolution: Equatable {
    case keep
    case stop
    case switchTo(projectId: String, taskId: String?)
    case addAsNewEntry(projectId: String, taskId: String?, startTime: Date, endTime: Date)
}
