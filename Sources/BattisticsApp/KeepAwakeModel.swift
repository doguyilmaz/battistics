import BattisticsCore
import Foundation
import Observation
import SwiftUI

/// Owns the live keep-awake session. Separate from `AppModel` because it has
/// nothing to do with reading the battery; it only holds an assertion and a
/// deadline.
@MainActor
@Observable
final class KeepAwakeModel {
    private(set) var session: KeepAwakeSession?

    @ObservationIgnored private let assertion = WakeAssertion()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    var isActive: Bool { session != nil }

    /// Last choices, so the popover's one-click toggle repeats what the user
    /// picked rather than a default they never asked for.
    var mode: KeepAwakeMode {
        get {
            KeepAwakeMode(rawValue: UserDefaults.standard.string(forKey: Prefs.keepAwakeMode) ?? "")
                ?? .displayOn
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Prefs.keepAwakeMode)
            // An assertion's type cannot change in place; retake it so a mode
            // switch applies immediately instead of at the next start.
            if let session {
                start(mode: newValue, duration: session.duration)
            }
        }
    }

    var duration: KeepAwakeDuration {
        get {
            KeepAwakeDuration(rawValue: UserDefaults.standard.integer(forKey: Prefs.keepAwakeDuration))
                ?? .indefinite
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Prefs.keepAwakeDuration) }
    }

    func start(mode: KeepAwakeMode, duration: KeepAwakeDuration, now: Date = Date()) {
        let new = KeepAwakeSession(mode: mode, duration: duration, startedAt: now)
        guard assertion.take(mode: mode, until: new.deadline, now: now) else {
            stop()
            return
        }
        UserDefaults.standard.set(mode.rawValue, forKey: Prefs.keepAwakeMode)
        UserDefaults.standard.set(duration.rawValue, forKey: Prefs.keepAwakeDuration)
        session = new
        scheduleExpiry(for: new, now: now)
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        assertion.release()
        session = nil
    }

    func toggle() {
        isActive ? stop() : start(mode: mode, duration: duration)
    }

    /// Seconds left, or nil when the session has no deadline or none is
    /// running. Derived from `startedAt`, never from a counter, so it stays
    /// correct through app nap and sleep.
    func remaining(at now: Date = Date()) -> TimeInterval? {
        session?.remaining(at: now)
    }

    /// One-shot, not a poll. The kernel releases the assertion on its own
    /// timeout regardless; this exists so the UI clears at the same moment.
    private func scheduleExpiry(for session: KeepAwakeSession, now: Date) {
        expiryTask?.cancel()
        guard let deadline = session.deadline else {
            expiryTask = nil
            return
        }
        let interval = max(deadline.timeIntervalSince(now), 0)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
}

// Display names live in the app target: `String(localized:)` inside the
// package would resolve against the package bundle, not the app's, so the
// Turkish strings would never be found.
extension KeepAwakeMode {
    var label: String {
        switch self {
        case .displayOn: String(localized: "Keep the display on")
        case .displayMaySleep: String(localized: "Let the display sleep")
        case .lidClosed: String(localized: "Stay awake with the lid closed")
        }
    }

    var caption: String? {
        switch self {
        case .displayOn: nil
        case .displayMaySleep: String(localized: "The screen turns off, the Mac keeps running.")
        case .lidClosed: String(localized: "Only works on power adapter; macOS ignores it on battery.")
        }
    }
}

extension KeepAwakeDuration {
    var label: String {
        switch self {
        case .fifteenMinutes: String(localized: "15 minutes")
        case .thirtyMinutes: String(localized: "30 minutes")
        case .oneHour: String(localized: "1 hour")
        case .twoHours: String(localized: "2 hours")
        case .fourHours: String(localized: "4 hours")
        case .sixHours: String(localized: "6 hours")
        case .twelveHours: String(localized: "12 hours")
        case .indefinite: String(localized: "Until I turn it off")
        }
    }

    /// Compact form for the popover strip and the duration chips.
    var shortLabel: String {
        switch self {
        case .fifteenMinutes: "15m"
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .fourHours: "4h"
        case .sixHours: "6h"
        case .twelveHours: "12h"
        case .indefinite: "∞"
        }
    }
}
