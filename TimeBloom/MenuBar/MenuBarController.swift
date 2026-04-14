//
//  MenuBarController.swift
//  TimeBloom
//
//  The AppKit half of the app. Owns:
//
//   • The `NSStatusItem` itself — the icon you see in the menu bar.
//   • The `NSPopover` that hosts our SwiftUI tree.
//   • The borderless `NSWindow` used for the idle-detected dialog.
//   • The `UNUserNotificationCenterDelegate` callbacks for inline
//     notification actions (Stop / Switch / Keep).
//
//  SwiftUI's `MenuBarExtra` is tempting on macOS 14, but it doesn't yet
//  give us programmatic control over showing/hiding the popover from
//  notification responses (or over the icon's tinted state during
//  recording), so we use AppKit for the shell and SwiftUI for the body.
//

import AppKit
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class MenuBarController: NSObject {

    // MARK: - Dependencies

    private let auth: AuthService
    private let settings: AppSettings
    private let store: TimerStore
    private let notifications: NotificationManager

    // MARK: - AppKit pieces

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var idleWindow: NSWindow?

    /// We want the icon to reflect the timer state: filled when running,
    /// stroked when idle. We use the canonical `withObservationTracking`
    /// recursion pattern: each invocation registers for "any change to
    /// the tracked properties", and the `onChange` closure re-registers
    /// itself. No polling, no Combine.
    ///
    /// A 1-second timer ticks the elapsed HH:MM display in the menu bar
    /// while a timer is running, similar to the Harvest app.
    private var menuBarTickTimer: Timer?

    init(
        auth: AuthService,
        settings: AppSettings,
        store: TimerStore,
        notifications: NotificationManager
    ) {
        self.auth = auth
        self.settings = settings
        self.store = store
        self.notifications = notifications

        // `.variableLength` lets the icon size itself; the system will
        // pad it to the standard 22pt height.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        self.popover = NSPopover()
        self.popover.behavior = .transient   // dismiss on outside-click
        self.popover.animates = true

        super.init()

        configureStatusButton()
        configurePopoverContent()
        configureNotificationDelegate()
        observeStoreChanges()
    }

    // MARK: - Setup

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.icon(running: false)
        button.image?.isTemplate = true   // tints with menu bar foreground
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "TimeBloom"
    }

    private func configurePopoverContent() {
        let host = NSHostingController(
            rootView: PopoverRootView(auth: auth, store: store)
        )
        // Sizing: SwiftUI provides intrinsic width; the popover uses it.
        popover.contentViewController = host
    }

    private func configureNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Re-render the icon when the timer starts/stops; pop the idle
    /// dialog when an event is published. Each `onChange` re-registers
    /// itself so observation is continuous.
    private func observeStoreChanges() {
        observeStatus()
        observeIdleEvents()
    }

    private func observeStatus() {
        // Read the tracked property AND do the side-effect inside the
        // tracking block so the next change re-fires this closure.
        withObservationTracking {
            self.refreshIcon()
            _ = self.store.status
        } onChange: { [weak self] in
            // `onChange` fires on the willSet edge — schedule the
            // re-registration on the next runloop tick so the new value
            // is observable when we read it.
            Task { @MainActor [weak self] in
                self?.observeStatus()
            }
        }
    }

    private func observeIdleEvents() {
        withObservationTracking {
            if let pending = self.store.pendingIdleEvent {
                self.showIdleAlert(for: pending)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeIdleEvents()
            }
        }
    }

    // MARK: - Click handling

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // Right-click (or Control-click) shows a small NSMenu instead of
        // the popover — useful for "Quit" without opening the UI.
        if event?.type == .rightMouseUp || NSEvent.modifierFlags.contains(.control) {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // Bring the app to the front so keyboard input goes to us.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        let menu = NSMenu()
        if case .running(let t) = store.status {
            menu.addItem(withTitle: "Running: \(t.project)", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Stop timer",
                         action: #selector(menuStop), keyEquivalent: "s").target = self
        } else {
            menu.addItem(withTitle: "No timer running", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open TimeBloom", action: #selector(menuOpenPopover), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Show the menu attached to the status item. We have to clear
        // `.menu` again right after to avoid suppressing left-clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuStop()        { Task { await store.stop() } }
    @objc private func menuOpenPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown { togglePopover(from: button) }
    }

    // MARK: - Idle alert window

    private func showIdleAlert(for event: IdleEvent) {
        // Don't double-present.
        if idleWindow != nil { return }

        let view = IdleAlertView(event: event, store: store) { [weak self] in
            self?.dismissIdleAlert()
        }
        let host = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = "TimeBloom"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()

        idleWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func dismissIdleAlert() {
        idleWindow?.close()
        idleWindow = nil
    }

    // MARK: - Icon + elapsed time rendering

    /// Updates the leaf icon AND the elapsed-time title shown in the
    /// menu bar. When a timer is running we display "0:42" (h:mm) next
    /// to the filled leaf, just like Harvest does. When stopped we show
    /// only the outline leaf with no title.
    private func refreshIcon() {
        guard let button = statusItem.button else { return }

        if let timer = store.status?.runningTimer {
            button.image = Self.icon(running: true)
            let elapsed = Int(Date.now.timeIntervalSince(timer.startTime))
            let h = elapsed / 3600
            let m = (elapsed % 3600) / 60
            button.title = String(format: " %d:%02d", h, m)
            startMenuBarTick()
        } else {
            button.image = Self.icon(running: false)
            button.title = ""
            stopMenuBarTick()
        }
        button.image?.isTemplate = true
    }

    /// Fires every 60 seconds to update the HH:MM display while a timer
    /// is running. We only need minute-level precision in the menu bar
    /// (the popover shows seconds).
    private func startMenuBarTick() {
        guard menuBarTickTimer == nil else { return }
        menuBarTickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
            }
        }
    }

    private func stopMenuBarTick() {
        menuBarTickTimer?.invalidate()
        menuBarTickTimer = nil
    }

    /// Returns the SF Symbol used for the current state. We keep the
    /// glyph subtle (a leaf for stopped, a filled leaf for running) so
    /// it doesn't dominate the menu bar.
    private static func icon(running: Bool) -> NSImage? {
        let name = running ? "leaf.fill" : "leaf"
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: running ? "Timer running" : "Timer stopped")?
            .withSymbolConfiguration(cfg)
    }
}

// MARK: - UNUserNotificationCenterDelegate
//
// Lets us (a) show notifications even when the app is "frontmost" (we're
// a menu bar app, so visually we're never frontmost), and (b) react to
// the inline action buttons.

extension MenuBarController: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.actionIdentifier
        await MainActor.run {
            switch id {
            case NotificationManager.ActionID.idleKeep:
                Task { await store.resolveIdle(.keep) }
            case NotificationManager.ActionID.idleStop, NotificationManager.ActionID.longStop:
                Task { await store.stop() }
            case NotificationManager.ActionID.idleSwitch:
                // Open the popover so the user can pick a project.
                if let button = statusItem.button { togglePopover(from: button) }
            case NotificationManager.ActionID.longKeep:
                break // user acknowledged; do nothing
            default:
                // Default tap (no action button) opens the popover.
                if let button = statusItem.button, !popover.isShown {
                    togglePopover(from: button)
                }
            }
        }
    }
}
