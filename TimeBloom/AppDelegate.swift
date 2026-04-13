//
//  AppDelegate.swift
//  TimeBloom
//
//  Owns the long-lived services and the menu-bar item itself. SwiftUI
//  doesn't have a first-class API for accessory-style apps yet, so we
//  bridge to AppKit here.
//

import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Long-lived shared state
    //
    // We construct these once at launch and pass them down by reference.
    // Anything @Observable lives here so that SwiftUI views (which are
    // re-created freely) keep getting the same single source of truth.

    private let auth = AuthService()
    private let settings = AppSettings()
    private let api: APIClient
    private let timerStore: TimerStore
    private let idleMonitor: IdleMonitor
    private let notifications = NotificationManager()

    /// The bridge between AppKit's `NSStatusItem`/`NSPopover` and our
    /// SwiftUI views. Holding it here keeps it alive for the app's lifetime.
    private var menuBarController: MenuBarController!

    override init() {
        // `APIClient` needs an `AuthService` so it can attach the bearer
        // token to every request. We build them in dependency order.
        self.api = APIClient(auth: auth)
        self.timerStore = TimerStore(api: api, notifications: notifications)
        self.idleMonitor = IdleMonitor(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Activation policy `.accessory` is the runtime equivalent of
        // `LSUIElement = YES` — no Dock icon, no main menu. Setting it
        // explicitly belt-and-braces the Info.plist value.
        NSApp.setActivationPolicy(.accessory)

        // Build the status bar item + popover and host `PopoverRootView`
        // inside it. The controller wires Cmd-clicks etc. on its own.
        menuBarController = MenuBarController(
            auth: auth,
            settings: settings,
            timerStore: timerStore,
            idleMonitor: idleMonitor,
            notifications: notifications
        )

        // Ask the user for notification permission once, lazily. The
        // system caches the answer; subsequent runs are no-ops.
        Task { await notifications.requestAuthorizationIfNeeded() }

        // Bind the idle monitor's events to the timer store so a single
        // place decides how to react (show dialog / post notification).
        idleMonitor.onIdleDetected = { [weak self] idleSeconds in
            Task { @MainActor in
                self?.timerStore.handleIdleDetected(seconds: idleSeconds)
            }
        }

        // Kick off background loops:
        // - Refresh the active timer from the server every 30s so we
        //   stay accurate if the user starts/stops on the web app.
        // - Run the idle monitor on a 5s heartbeat.
        timerStore.startBackgroundRefresh()
        idleMonitor.start()

        // If we already have a token, fetch the current state immediately.
        if auth.hasValidToken {
            Task { await timerStore.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleMonitor.stop()
        timerStore.stopBackgroundRefresh()
    }
}
