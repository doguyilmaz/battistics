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

    private(set) var isChanging = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let helper: PowerHelperClient
    @ObservationIgnored private var leaseTask: Task<Void, Never>?

    var mode: KeepAwakeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Prefs.keepAwakeMode)
            if let session, oldValue != mode {
                start(mode: mode, duration: session.duration, now: session.startedAt)
            }
        }
    }

    var duration: KeepAwakeDuration {
        didSet { UserDefaults.standard.set(duration.rawValue, forKey: Prefs.keepAwakeDuration) }
    }

    init(helper: PowerHelperClient) {
        self.helper = helper
        mode = KeepAwakeMode(rawValue: UserDefaults.standard.string(forKey: Prefs.keepAwakeMode) ?? "") ?? .displayOn
        duration = KeepAwakeDuration(rawValue: UserDefaults.standard.integer(forKey: Prefs.keepAwakeDuration)) ?? .indefinite
    }

    func start(mode: KeepAwakeMode, duration: KeepAwakeDuration, now: Date = Date()) {
        guard !isChanging else { return }
        isChanging = true
        errorMessage = nil
        let previous = session
        Task {
            defer { isChanging = false }
            do {
                if mode == .lidClosed {
                    try await helper.setLidSleepLease(true)
                } else if previous?.mode == .lidClosed {
                    try await helper.setLidSleepLease(false)
                }
                let new = KeepAwakeSession(mode: mode, duration: duration, startedAt: now)
                guard !new.hasExpired(at: Date()),
                    assertion.take(mode: mode, until: new.deadline) else {
                    if mode == .lidClosed { try await helper.setLidSleepLease(false) }
                    throw CocoaError(.featureUnsupported)
                }
                leaseTask?.cancel()
                session = new
                scheduleExpiry(for: new, now: Date())
                if mode == .lidClosed { renewLease() }
            } catch {
                assertion.release()
                expiryTask?.cancel()
                leaseTask?.cancel()
                session = nil
                errorMessage = String(localized: "Could not start Keep Awake. For closed-lid mode, install or repair the power helper in System settings.")
            }
        }
    }

    func stop() {
        guard !isChanging else { return }
        let wasLidClosed = session?.mode == .lidClosed
        expiryTask?.cancel()
        expiryTask = nil
        leaseTask?.cancel()
        leaseTask = nil
        assertion.release()
        session = nil
        guard wasLidClosed else { return }
        isChanging = true
        Task {
            defer { isChanging = false }
            do { try await helper.setLidSleepLease(false) }
            catch {
                errorMessage = String(localized: "Could not confirm restoring sleep. The helper will retry after its lease expires; repair the helper if sleep remains disabled.")
            }
        }
    }

    func toggle() {
        isActive ? stop() : start(mode: mode, duration: duration)
    }

    func sleepDisplayNow() {
        Task {
            let success = await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["displaysleepnow"]
                do { try process.run() } catch { return false }
                process.waitUntilExit()
                return process.terminationStatus == 0
            }.value
            if !success { errorMessage = String(localized: "macOS could not put the display to sleep.") }
        }
    }

    private func renewLease() {
        leaseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.session?.mode == .lidClosed else { return }
                do { try await self.helper.setLidSleepLease(true) }
                catch {
                    self.errorMessage = String(localized: "Lost the power helper connection. Keep Awake has stopped.")
                    self.stop()
                    return
                }
            }
        }
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
        case .displayMaySleep: String(localized: "The display follows its sleep timer while the Mac keeps running.")
        case .lidClosed: String(localized: "Requires the power helper. Keeps the Mac running with its lid closed on battery or adapter.")
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
