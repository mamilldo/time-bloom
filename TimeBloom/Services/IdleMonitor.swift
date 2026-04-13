//
//  IdleMonitor.swift
//  TimeBloom
//
//  Polls the system's "seconds since last input event" counter on a 5s
//  cadence. When it crosses the user-configured threshold AND a timer is
//  actually running, we fire `onIdleDetected` once. We then arm a
//  one-shot guard so we don't keep firing every 5 seconds for the entire
//  idle period — the next fire only happens after activity resumes.
//
//  Quartz's `CGEventSource.secondsSinceLastEventType` reads kernel-level
//  event timestamps, so we don't need to install a global event tap (and
//  thus don't need Accessibility permission). It works in a sandboxed
//  app on macOS 14.
//

import AppKit
import Foundation

@MainActor
final class IdleMonitor {

    /// Fired once per idle episode. The TimeInterval is "seconds idle at
    /// the moment of detection" — useful if you want to subtract idle
    /// time from a manually-edited entry.
    var onIdleDetected: ((TimeInterval) -> Void)?

    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?

    /// `true` while the user is currently in an idle episode we've
    /// already reported. Reset to `false` as soon as input resumes.
    private var alreadyReportedThisEpisode = false

    /// Heartbeat interval. 5 seconds is plenty — we don't need
    /// sub-second precision for "are you at your desk?".
    private let pollInterval: TimeInterval = 5

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() {
        let idle = Self.systemIdleSeconds()
        let threshold = TimeInterval(settings.idleThresholdMinutes * 60)

        if idle >= threshold {
            if !alreadyReportedThisEpisode {
                alreadyReportedThisEpisode = true
                onIdleDetected?(idle)
            }
        } else {
            // Below threshold means the user is back. Re-arm so the next
            // genuine idle episode triggers a fresh notification.
            alreadyReportedThisEpisode = false
        }
    }

    /// Wraps the Quartz call. Uses `combinedSessionState` so it sees
    /// keyboard, mouse, and trackpad together — the right notion of
    /// "user activity" for a desk app. The `~UInt32(0)` literal is the
    /// documented "any event type" sentinel (`kCGAnyInputEventType`
    /// in the C headers).
    static func systemIdleSeconds() -> TimeInterval {
        let anyEventType = CGEventType(rawValue: ~UInt32(0))!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                       eventType: anyEventType)
    }
}
