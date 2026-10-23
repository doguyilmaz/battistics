import AppKit
import BattisticsCore
import BattisticsRemote
import Foundation
import Observation
import SwiftUI

/// Owns the live keep-awake assertion, deadline, and protection lifecycle.
/// AppModel feeds battery readings to the safety monitor independently of UI.
@MainActor
@Observable
final class KeepAwakeModel {
    private enum StartFailure: Error { case protection(KeepAwakeSafetyPolicy.Event) }
    let safety: KeepAwakeSafetyMonitor
    private(set) var session: KeepAwakeSession?
    private(set) var sessionName: String?
    private(set) var sessionOrigin: RemoteStatus.Origin = .manual
    private(set) var lastEnd: RemoteStatus.LastEnd?

    @ObservationIgnored private let assertion = WakeAssertion()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    var isActive: Bool { session != nil }

    private(set) var isChanging = false
    private(set) var errorMessage: String?
    private(set) var isStoppedReasonInformational = false
    @ObservationIgnored private let helper: PowerHelperClient
    @ObservationIgnored private var leaseTask: Task<Void, Never>?
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored var onOwnershipReleased: ((String) -> Void)?
    var sessionIdentifier: String? { sessionID }
    var isAwaitingHelperApproval: Bool { approvalTask != nil }
    @ObservationIgnored private var reconcilingSessionID: String?
    @ObservationIgnored private let notice = KeepAwakeNoticeController()
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// Waits, bounded, for the user to allow the helper in Login Items, then
    /// starts the closed-lid session they asked for.
    private var approvalTask: Task<Void, Never>?
    /// Keeps App Nap from stretching the renewal timer past the helper's
    /// 45-second lease while the lid is shut and nothing of ours is visible.
    @ObservationIgnored private var renewalActivity: NSObjectProtocol?

    var mode: KeepAwakeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Prefs.keepAwakeMode)
            if let session, session.mode != mode {
                let profile = sessionOrigin == .profile ? sessionName : nil
                start(mode: mode, duration: session.duration, now: session.startedAt,
                      name: profile, origin: profile == nil ? .manual : .profile)
            } else if mode != .lidClosed, approvalTask != nil {
                // Nothing left to wait for once closed-lid is no longer wanted.
                cancelApprovalWait()
                errorMessage = nil
            }
        }
    }

    var duration: KeepAwakeDuration {
        didSet {
            UserDefaults.standard.set(duration.rawValue, forKey: Prefs.keepAwakeDuration)
            if let session, session.duration != duration { retime(session, to: duration) }
        }
    }

    /// Automation does not overwrite the user's next-session defaults. Pickers
    /// still show the actual running mode and let the user take over explicitly.
    var displayedMode: KeepAwakeMode {
        get { session?.mode ?? mode }
        set { mode = newValue }
    }

    var displayedDuration: KeepAwakeDuration {
        get { session?.duration ?? duration }
        set { duration = newValue }
    }

    init(helper: PowerHelperClient) {
        self.helper = helper
        safety = KeepAwakeSafetyMonitor(notice: notice)
        mode = KeepAwakeMode(rawValue: UserDefaults.standard.string(forKey: Prefs.keepAwakeMode) ?? "") ?? .displayOn
        duration = KeepAwakeDuration(rawValue: UserDefaults.standard.integer(forKey: Prefs.keepAwakeDuration)) ?? .indefinite
        safety.onStop = { [weak self] event in
            guard let self else { return }
            let id = self.sessionID ?? UUID().uuidString
            self.stop(reason: event == .thermalStop ? .thermal : .battery)
            self.showSafetyReason(event, id: id)
        }
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

    @discardableResult
    func start(profile: KeepAwakeProfile) -> Task<Void, Never>? {
        guard !isActive, !isChanging, !isAwaitingHelperApproval else { return nil }
        return start(mode: profile.mode, duration: profile.duration, name: profile.title, origin: .profile)
    }

    @discardableResult
    func start(mode: KeepAwakeMode, duration: KeepAwakeDuration, now: Date = Date(),
               id: String = UUID().uuidString, allowHelperSetup: Bool = true, name: String? = nil,
               origin: RemoteStatus.Origin = .manual) -> Task<Void, Never>? {
        guard !isChanging else { return nil }
        if let event = safety.blockingEvent() {
            let wasActive = isActive
            if wasActive { stop() }
            showSafetyReason(event, id: UUID().uuidString, starting: !wasActive)
            return nil
        }
        cancelApprovalWait()
        let previousLeaseID = session?.mode == .lidClosed ? sessionID : nil
        clearLocalSession()
        sessionID = id
        isChanging = true
        errorMessage = nil
        isStoppedReasonInformational = false
        notice.dismiss()
        return Task {
            defer {
                isChanging = false
                // A safety stop may immediately start async lease cleanup.
                // Do not overwrite that cleanup's busy state afterward.
                if sessionID == id, session != nil { safety.startSession() }
            }
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
                    if allowHelperSetup { try await helper.prepareForLidSleep() }
                    guard sessionID == id else { return }
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
                // Authorization can take long enough for charge or thermal
                // conditions to change. Recheck before creating the assertion.
                if let event = safety.blockingEvent() { throw StartFailure.protection(event) }
                let new = KeepAwakeSession(mode: mode, duration: duration, startedAt: now)
                guard !new.hasExpired(at: Date()),
                    assertion.take(mode: mode, until: new.deadline) else {
                    throw CocoaError(.featureUnsupported)
                }
                session = new
                sessionName = name
                sessionOrigin = origin
                scheduleExpiry(for: new, now: Date())
                if mode == .lidClosed {
                    renewalActivity = ProcessInfo.processInfo.beginActivity(
                        options: .userInitiatedAllowingIdleSystemSleep,
                        reason: "Renewing the closed-lid Keep Awake lease")
                    renewLease(sessionID: id)
                }
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
                // Only an acquisition that reached the helper can have mutated
                // the setting. A failed preparation or a rejected preflight
                // never needs a release selector.
                if helper.hasLidSleepLeaseSession(id) {
                    let confirmed = await cleanUpAcquisition(sessionID: id)
                    guard sessionID == id else { return }
                    clearLocalSession()
                    if !confirmed { return }
                } else {
                    guard sessionID == id else { return }
                    clearLocalSession()
                }
                showStartFailure(error, duration: duration, allowHelperSetup: allowHelperSetup)
            }
        }
    }

    private func showStartFailure(_ error: Error, duration: KeepAwakeDuration, allowHelperSetup: Bool) {
        isStoppedReasonInformational = false
        switch error {
        case StartFailure.protection(let event):
            showSafetyReason(event, id: UUID().uuidString, starting: true)
        case PowerHelperClient.Failure.needsApproval:
            guard allowHelperSetup else {
                errorMessage = String(localized: "Set up the power helper in Battistics before using closed-lid automation.")
                return
            }
            isStoppedReasonInformational = true
            errorMessage = String(localized: "Allow Battistics in System Settings > General > Login Items & Extensions. Closed-lid Keep Awake starts as soon as it is allowed.")
            helper.openLoginItemsSettings()
            waitForHelperApproval(duration: duration)
        case PowerHelperClient.Failure.installFailed(let domain, let code):
            errorMessage = String(localized: "macOS did not install the power helper that closed-lid mode needs.") + " (\(domain) \(code))"
        case PowerHelperClient.Failure.outdated:
            errorMessage = String(localized: "An older power helper is still running. Restart the Mac to replace it, then try again.")
        case PowerHelperClient.Failure.unsignedBuild:
            errorMessage = PowerHelperClient.unsignedBuildMessage
        case is PowerHelperClient.Failure:
            errorMessage = String(localized: "The power helper did not respond, even after it was registered again. Use Repair in the Power pane or restart the Mac.")
        default:
            errorMessage = String(localized: "macOS did not accept the Keep Awake request. Try again.")
        }
    }

    /// Polls a cheap registration read for a few minutes at most: no
    /// notification reports the approval, and returning to Battistics is not
    /// guaranteed to activate a menu bar app.
    private func waitForHelperApproval(duration: KeepAwakeDuration) {
        approvalTask?.cancel()
        approvalTask = Task { [weak self] in
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                // A different choice since then wins over the old request.
                guard self.session == nil, self.mode == .lidClosed else { break }
                self.helper.refreshStatusIfChanged()
                if self.helper.isInstalled {
                    self.approvalTask = nil
                    self.start(mode: .lidClosed, duration: duration)
                    return
                }
            }
            self?.approvalTask = nil
        }
    }

    private func cancelApprovalWait() {
        approvalTask?.cancel()
        approvalTask = nil
    }

    func stop(reason: RemoteStatus.EndReason = .user) {
        if session != nil { lastEnd = .init(reason: reason, at: Date()) }
        let leaseID = session?.mode == .lidClosed ? sessionID : nil
        if approvalTask != nil {
            cancelApprovalWait()
            errorMessage = nil
        }
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
        let endedID = sessionID
        safety.endSession()
        sessionID = nil
        expiryTask?.cancel()
        expiryTask = nil
        leaseTask?.cancel()
        leaseTask = nil
        if let renewalActivity {
            ProcessInfo.processInfo.endActivity(renewalActivity)
            self.renewalActivity = nil
        }
        assertion.release()
        session = nil
        sessionName = nil
        sessionOrigin = .manual
        if let endedID { onOwnershipReleased?(endedID) }
    }

    func toggle() {
        if isActive { stop() } else { start(mode: mode, duration: duration) }
    }

    func sleepDisplayNow() {
        let requestedSessionID = sessionID
        Task {
            let success: Bool
            do {
                _ = try await BoundedCommand.run(
                    executable: "/usr/bin/pmset", arguments: ["displaysleepnow"],
                    timeout: 5, maximumOutputBytes: 16_384)
                success = true
            } catch { success = false }
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
        safety.refresh()
        guard let session else { return }
        if session.hasExpired(at: Date()) {
            stop(reason: .timer)
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
        if session != nil { lastEnd = .init(reason: .failure, at: Date()) }
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

    private func showSafetyReason(_ event: KeepAwakeSafetyPolicy.Event, id: String, starting: Bool = false) {
        isStoppedReasonInformational = true
        errorMessage = KeepAwakeSafetyMonitor.message(for: event, starting: starting)
        notice.show(sessionID: id, message: errorMessage ?? "",
                    title: starting ? String(localized: "Keep Awake not started") : String(localized: "Keep Awake stopped"))
    }

    /// A new duration counts from now. The closed-lid lease is untouched; it
    /// does not carry a deadline of its own.
    private func retime(_ current: KeepAwakeSession, to duration: KeepAwakeDuration) {
        guard !isChanging else { return }
        let now = Date()
        let new = KeepAwakeSession(mode: current.mode, duration: duration, startedAt: now)
        guard assertion.take(mode: new.mode, until: new.deadline, now: now) else {
            stop(reason: .failure)
            isStoppedReasonInformational = false
            errorMessage = String(localized: "macOS did not accept the Keep Awake request. Try again.")
            return
        }
        session = new
        scheduleExpiry(for: new, now: now)
        // A duration picked on this Mac takes the session over from automation or a phone.
        if sessionOrigin != .profile {
            sessionOrigin = .manual
            sessionName = nil
        }
        if let sessionID { onOwnershipReleased?(sessionID) }
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
            self?.stop(reason: .timer)
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
        case .lidClosed: String(localized: "Uses the power helper, set up the first time you turn this on. Keeps the Mac running with its lid closed on battery or adapter.")
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
}
