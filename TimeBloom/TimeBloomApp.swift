//
//  TimeBloomApp.swift
//  TimeBloom
//
//  The SwiftUI @main entry point.
//
//  We intentionally do *not* declare a `WindowGroup` or `Settings` scene
//  here — the entire UI lives in a `NSStatusItem`/`NSPopover` constructed
//  by `MenuBarController`. SwiftUI insists on having at least one scene,
//  so we attach a `Settings` scene that we never present (its absence in
//  combination with `LSUIElement = YES` would be acceptable too, but
//  declaring it future-proofs us if we add a real Settings window later).
//

import SwiftUI

@main
struct TimeBloomApp: App {

    /// Hooks SwiftUI up to a classic AppKit delegate. `AppDelegate` is what
    /// constructs the status bar item and owns long-lived services.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An empty `Settings` scene is the smallest legal scene SwiftUI
        // accepts. Because `LSUIElement` is YES, it never auto-presents
        // and never adds a Dock/menu bar entry of its own.
        Settings {
            EmptyView()
        }
    }
}
