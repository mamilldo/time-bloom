//
//  AppSettings.swift
//  TimeBloom
//
//  User preferences backed by `UserDefaults`. Specifically NOT for tokens
//  or anything sensitive — those go in Keychain. This is for thresholds
//  and toggles the user can change in a future Settings window.
//
//  Marked `@Observable` so binding `Slider($settings.idleThresholdMinutes)`
//  in a view automatically writes back to UserDefaults.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {

    /// How many minutes of inactivity before we ask the user "are you
    /// still working?". Default 10 minutes.
    var idleThresholdMinutes: Int {
        didSet { defaults.set(idleThresholdMinutes, forKey: Keys.idleThreshold) }
    }

    /// How many hours a continuous timer can run before we nag the user.
    /// Default 4 — long enough to not bother focused work, short enough
    /// to catch "I forgot it was running overnight".
    var longRunningTimerHours: Int {
        didSet { defaults.set(longRunningTimerHours, forKey: Keys.longRunningHours) }
    }

    /// Whether to fire a UNUserNotification each time the timer auto-
    /// stops or the server reports it stopped from another device.
    var notifyOnAutoStop: Bool {
        didSet { defaults.set(notifyOnAutoStop, forKey: Keys.notifyAutoStop) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Reading then writing the same key in `didSet` is fine — the
        // first read just hits the in-memory plist cache.
        let storedIdle = defaults.object(forKey: Keys.idleThreshold) as? Int
        self.idleThresholdMinutes = storedIdle ?? 10

        let storedLong = defaults.object(forKey: Keys.longRunningHours) as? Int
        self.longRunningTimerHours = storedLong ?? 4

        let storedNotify = defaults.object(forKey: Keys.notifyAutoStop) as? Bool
        self.notifyOnAutoStop = storedNotify ?? true
    }

    private enum Keys {
        static let idleThreshold     = "idleThresholdMinutes"
        static let longRunningHours  = "longRunningTimerHours"
        static let notifyAutoStop    = "notifyOnAutoStop"
    }
}
