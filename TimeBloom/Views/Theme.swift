//
//  Theme.swift
//  TimeBloom
//
//  Centralised colours and metrics. Keeping them here means the dark
//  green brand colour can be tweaked in one place — no `.foregroundColor`
//  calls scattered across views with hard-coded hex values.
//

import SwiftUI

enum Theme {

    /// Brand dark green. The `dark` variant is slightly lighter so it
    /// reads correctly against macOS 14's translucent dark-mode popover
    /// background.
    static let brand = Color(
        light: Color(red: 0.18, green: 0.42, blue: 0.30),
        dark:  Color(red: 0.42, green: 0.74, blue: 0.55)
    )

    /// Used for the running-timer indicator dot.
    static let runningIndicator = Color(
        light: Color(red: 0.18, green: 0.42, blue: 0.30),
        dark:  Color(red: 0.46, green: 0.80, blue: 0.58)
    )

    /// Popover content has a fixed width so multi-line task names don't
    /// reflow the popover when projects change.
    static let popoverWidth: CGFloat = 360
}

private extension Color {
    /// SwiftUI doesn't expose a clean per-trait initializer outside of an
    /// asset catalog, so we wrap one with `NSColor(name:dynamicProvider:)`.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
