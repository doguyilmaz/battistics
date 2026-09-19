import AppKit
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
    private(set) var isStoppedReasonInformational = false
    @ObservationIgnored private let helper: PowerHelperClient
    @ObservationIgnored private var leaseTask: Task<Void, Never>?
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var reconcilingSessionID: String?
    @ObservationIgnored private let notice = KeepAwakeNoticeController()
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

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
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.reconcileAfterWakeOrActivation() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.reconcileAfterWakeOrActivation() }
        }
    }

    func start(mode: KeepAwakeMode, duration: KeepAwakeDuration, now: Date = Date()) {
        guard !isChanging else { return }
        let previousLeaseID = session?.mode == .lidClosed ? sessionID : nil
        clearLocalSession()
        let id = UUID().uuidString
        sessionID = id
        isChanging = true
        errorMessage = nil
        isStoppedReasonInformational = false
        notice.dismiss()
        Task {
            defer { isChanging = false }
            var releasingPrevious = previousLeaseID != nil
            do {
                if let previousLeaseID {
                    let result = try await helper.releaseLidSleepLease(previousLeaseID)
                    guard result == .success || result == .inactive else {
                        if sessionID == id {
                            stopAfterLeaseFailure(result, sessionID: id, releaseFailed: true)
                        } else {
                            showStoppedReason(result, sessionID: id, releaseFailed: true)
                        }
                        return
                    }
                    guard sessionID == id else { return }
                    releasingPrevious = false
                }
                guard sessionID == id else { return }
                if mode == .lidClosed {
                    let result = try await helper.acquireLidSleepLease(id) { [weak self] in
                        self?.sessionID == id
                    }
                    guard sessionID == id else {
                        if result == .success {
                            _ = await cleanUpAcquisition(sessionID: id)
                        } else if result != .inactive {
                            showStoppedReason(result, sessionID: id)
                        }
                        return
                    }
                    guard result == .success else {
                        stopAfterLeaseFailure(result, sessionID: id)
                        return
                    }
                }
                let new = KeepAwakeSession(mode: mode, duration: duration, startedAt: now)
                guard !new.hasExpired(at: Date()),
                    assertion.take(mode: mode, until: new.deadline) else {
                    throw CocoaError(.featureUnsupported)
                }
                session = new
                scheduleExpiry(for: new, now: Date())
                if mode == .lidClosed { renewLease(sessionID: id) }
            } catch PowerHelperClient.Failure.unknownLeaseStatus {
                // An unrecognized wire result does not authorize rollback.
                if sessionID == id {
                    stopAfterLeaseFailure(nil, sessionID: id, releaseFailed: releasingPrevious)
                } else {
                    showStoppedReason(nil, sessionID: id, releaseFailed: releasingPrevious)
                }
            } catch {
                if releasingPrevious {
                    if sessionID == id {
                        stopAfterLeaseFailure(nil, sessionID: id, releaseFailed: true)
                    } else {
                        showStoppedReason(nil, sessionID: id, releaseFailed: true)
                    }
                    return
                }
                // Only a v3 acquisition can have mutated the setting. An older
                // helper or a rejected preflight never needs a release selector.
                if helper.hasLidSleepLeaseSession(id) {
                    let confirmed = await cleanUpAcquisition(sessionID: id)
                    guard sessionID == id else { return }
                    clearLocalSession()
                    if !confirmed { return }
                } else {
                    guard sessionID == id else { return }
                    clearLocalSession()
                }
                errorMessage = String(localized: "Could not start Keep Awake. For closed-lid mode, install or repair the power helper in System settings.")
            }
        }
    }

    func stop() {
        let leaseID = session?.mode == .lidClosed ? sessionID : nil
        clearLocalSession()
        // A pending start owns its cleanup and keeps changes serialized until
        // its reply arrives. Invalidating sessionID prevents it from starting.
        guard !isChanging, let leaseID else { return }
        isChanging = true
        Task {
            defer { isChanging = false }
            do {
                let result = try await helper.releaseLidSleepLease(leaseID)
                if result == .ownershipLost {
                    showStoppedReason(result, sessionID: leaseID, releaseFailed: true)
                } else if result != .success && result != .inactive {
                    showStoppedReason(result, sessionID: leaseID, releaseFailed: true)
                }
            } catch {
                showStoppedReason(nil, sessionID: leaseID, releaseFailed: true)
            }
        }
    }

    private func cleanUpAcquisition(sessionID id: String) async -> Bool {
        do {
            let result = try await helper.releaseLidSleepLease(id)
            if result == .success || result == .inactive { return true }
            showStoppedReason(result, sessionID: id, releaseFailed: true)
        } catch {
            showStoppedReason(nil, sessionID: id, releaseFailed: true)
        }
        return false
    }

    private func clearLocalSession() {
        sessionID = nil
        expiryTask?.cancel()
        expiryTask = nil
        leaseTask?.cancel()
        leaseTask = nil
        assertion.release()
        session = nil
    }

    func toggle() {
        isActive ? stop() : start(mode: mode, duration: duration)
    }

    func sleepDisplayNow() {
        let requestedSessionID = sessionID
        Task {
            let success = await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["displaysleepnow"]
                do { try process.run() } catch { return false }
                process.waitUntilExit()
                return process.terminationStatus == 0
            }.value
            // A late display command must not replace the retained reason for
            // a session that stopped while the command was running.
            guard sessionID == requestedSessionID else { return }
            if !success {
                isStoppedReasonInformational = false
                errorMessage = String(localized: "macOS could not put the display to sleep.")
            }
        }
    }

    private func renewLease(sessionID id: String) {
        leaseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.sessionID == id else { return }
                await self.reconcileLease(sessionID: id)
            }
        }
    }

    private func reconcileAfterWakeOrActivation() {
        guard let session else { return }
        if session.hasExpired(at: Date()) {
            stop()
        } else if session.mode == .lidClosed, let id = sessionID {
            Task { await reconcileLease(sessionID: id) }
        }
    }

    private func reconcileLease(sessionID id: String) async {
        guard sessionID == id, session?.mode == .lidClosed,
            reconcilingSessionID != id else { return }
        reconcilingSessionID = id
        defer { if reconcilingSessionID == id { reconcilingSessionID = nil } }
        do {
            let result = try await helper.renewLidSleepLease(id)
            guard sessionID == id else { return }
            if result != .success { stopAfterLeaseFailure(result, sessionID: id) }
        } catch {
            guard sessionID == id else { return }
            // Unknown results and transport failures cannot prove an external
            // change. Stop renewing and let the helper resolve its own lease.
            stopAfterLeaseFailure(nil, sessionID: id)
        }
    }

    private func stopAfterLeaseFailure(
        _ result: LidSleepLeaseResult?, sessionID id: String, releaseFailed: Bool = false
    ) {
        guard sessionID == id else { return }
        clearLocalSession()
        // Ownership was lost: no release/rollback RPC and no automatic restart.
        showStoppedReason(result, sessionID: id, releaseFailed: releaseFailed)
    }

    private func showStoppedReason(
        _ result: LidSleepLeaseResult?, sessionID id: String, releaseFailed: Bool = false
    ) {
        let message: String
        if result == .ownershipLost {
            message = String(localized: "The system sleep setting changed elsewhere. Your current setting was kept.")
        } else if releaseFailed || result == .failed || result == .unavailable || result == nil {
            message = String(localized: "Keep Awake stopped, but the system sleep setting could not be confirmed. Check your system sleep settings.")
        } else if result == .inactive {
            message = String(localized: "The closed-lid Keep Awake session ended.")
        } else {
            message = String(localized: "The power helper could not confirm the closed-lid session. Keep Awake has stopped.")
        }
        isStoppedReasonInformational = result == .ownershipLost || result == .inactive
        errorMessage = message
        notice.show(sessionID: id, message: message)
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
