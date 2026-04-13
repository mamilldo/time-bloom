//
//  NotificationManager.swift
//  TimeBloom
//
//  Wraps `UNUserNotificationCenter` for our two notification flavours:
//
//  1. "You've been idle for X minutes" — actionable: Keep / Stop / Switch.
//     The Switch action opens the popover; the others execute inline via
//     the `UNNotificationAction` callback in `MenuBarController`.
//
//  2. "Your timer has been running for 4 hours" — actionable: Keep going
//     / Stop now.
//
//  We register the categories at startup so the action buttons appear in
//  Notification Center. Because this is a sandboxed menu bar app we also
//  need the user's permission, requested lazily on first notification.
//

import Foundation
@preconcurrency import UserNotifications

actor NotificationManager {

    // Category IDs are referenced both here and in `MenuBarController`
    // when handling the user's response. Keep them as constants.
    enum CategoryID {
        static let idle        = "IDLE_DETECTED"
        static let longRunning = "LONG_RUNNING_TIMER"
    }

    enum ActionID {
        static let idleKeep    = "IDLE_KEEP"
        static let idleStop    = "IDLE_STOP"
        static let idleSwitch  = "IDLE_SWITCH"

        static let longKeep    = "LONG_KEEP"
        static let longStop    = "LONG_STOP"
    }

    private var hasRequestedAuthorization = false

    /// Ask once per launch. The OS caches the answer across launches so
    /// repeated calls are essentially free, but skipping the round-trip
    /// keeps the launch path tidy.
    func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // A denied permission is fine — the rest of the app still
            // works, we just won't get banner alerts.
            return
        }
        registerCategories()
    }

    private func registerCategories() {
        let idleCategory = UNNotificationCategory(
            identifier: CategoryID.idle,
            actions: [
                UNNotificationAction(identifier: ActionID.idleKeep,
                                     title: "Keep idle as work time",
                                     options: []),
                UNNotificationAction(identifier: ActionID.idleSwitch,
                                     title: "Switch task…",
                                     options: [.foreground]),
                UNNotificationAction(identifier: ActionID.idleStop,
                                     title: "Stop timer",
                                     options: [.destructive]),
            ],
            intentIdentifiers: [],
            options: []
        )

        let longCategory = UNNotificationCategory(
            identifier: CategoryID.longRunning,
            actions: [
                UNNotificationAction(identifier: ActionID.longKeep,
                                     title: "Keep running",
                                     options: []),
                UNNotificationAction(identifier: ActionID.longStop,
                                     title: "Stop timer",
                                     options: [.destructive]),
            ],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([idleCategory, longCategory])
    }

    // MARK: - Posting

    func postIdleDetected(project: String, idleMinutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Still working on \(project)?"
        content.body  = "You've been idle for \(idleMinutes) minutes."
        content.sound = .default
        content.categoryIdentifier = CategoryID.idle
        await deliver(content)
    }

    func postLongRunningTimer(project: String, hours: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Timer has run for over \(hours) hours"
        content.body  = "Still working on \(project)? Stop it if you forgot."
        content.sound = .default
        content.categoryIdentifier = CategoryID.longRunning
        await deliver(content)
    }

    private func deliver(_ content: UNNotificationContent) async {
        // `nil` trigger = deliver immediately.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
