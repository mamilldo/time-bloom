//
//  AppDelegate.swift
//  TimeBloom
//
//  Owns the long-lived services and the menu-bar item itself. SwiftUI
//  doesn't have a first-class API for accessory-style apps with
//  programmatic notification handling yet, so we bridge to AppKit here.
//

import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Long-lived shared state
    //
    // We construct these once at launch and pass them down by reference.
    // Anything `@Observable` lives here so that SwiftUI views (which are
    // re-created freely) keep getting the same single source of truth.

    private let auth = AuthService()
    private let settings = AppSettings()
    private let notifications = NotificationManager()
    private let api: APIClient
    private let store: TimerStore
    private let idleMonitor: IdleMonitor

    /// The bridge between AppKit's `NSStatusItem`/`NSPopover` and our
    /// SwiftUI views. Holding it here keeps it alive for the app's
    /// lifetime — without a reference, ARC would deallocate the status
    /// item and the icon would vanish.
    private var menuBarController: MenuBarController!

    override init() {
        // Build services in dependency order.
        self.api         = APIClient(auth: auth)
        self.store       = TimerStore(api: api, auth: auth, settings: settings, notifications: notifications)
        self.idleMonitor = IdleMonitor(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Activation policy `.accessory` is the runtime equivalent of
        // `LSUIElement = YES` — no Dock icon, no main menu. Setting it
        // explicitly belt-and-braces the Info.plist value so the app
        // behaves correctly even if the plist is mis-edited.
        NSApp.setActivationPolicy(.accessory)

        // Build the status bar item + popover and host `PopoverRootView`
        // inside it.
        menuBarController = MenuBarController(
            auth: auth,
            settings: settings,
            store: store,
            notifications: notifications
        )

        // Ask the user for notification permission once, lazily. The
        // system caches the answer; subsequent launches are no-ops.
        Task { await notifications.requestAuthorizationIfNeeded() }

        // Bind the idle monitor's events to the timer store so a single
        // place decides how to react (show dialog / post notification).
        idleMonitor.onIdleDetected = { [weak self] idleSeconds in
            Task { @MainActor in
                self?.store.handleIdleDetected(seconds: idleSeconds)
            }
        }

        // Kick off background loops.
        store.startBackgroundLoops()
        idleMonitor.start()

        // If we already have stored credentials, fetch the current
        // server state immediately so the icon reflects reality before
        // the first 30-second poll fires.
        if auth.hasStoredCredentials {
            Task { await store.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleMonitor.stop()
        store.stopBackgroundLoops()
    }
}
