import BattisticsCore
import Foundation
import AppKit
import Observation

/// One copy of macOS's power configuration, shared by the System pane and the
/// popover so the two can never disagree about what the system says.
@MainActor
@Observable
final class PowerSettingsModel {
    private(set) var settings: PowerSettings?

    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshGeneration: UInt = 0

    init() {
        // Same reasoning as the helper's status: these can be changed in
        // System Settings behind our back, and coming back to Battistics is
        // exactly the moment a stale value would be noticed. One ~9ms read
        // per activation, never on a timer.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    @discardableResult
    func refresh() async -> PowerSettings? {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let refreshed = await PowerSettingsReader.fetch()
        if generation == refreshGeneration {
            settings = refreshed
        }
        return refreshed
    }

    enum Outcome {
        case applied
        /// The user dismissed the password prompt. Not an error.
        case cancelled
        case failed
    }

    /// Applies a change, asking for permission first if it is not already
    /// held. Controls stay live whether or not permission exists, so a change
    /// is one click plus at most one prompt, rather than an unlock step the
    /// user has to discover first.
    ///
    /// Nothing is assumed to have landed: this re-reads afterwards and the UI
    /// renders what the system reports, so a cancelled prompt or a failed
    /// write leaves the controls showing reality.
    @discardableResult
    func apply(
        _ change: PowerChange, using auth: PowerAuthorization, helper: PowerHelperClient
    ) async -> Outcome {
        var outcome = Outcome.applied
        var helperHandledIt = false
        if helper.canApply {
            // The daemon is already root, so this needs no authorization and
            // shows no prompt.
            do {
                try await helper.apply(change)
                helperHandledIt = true
            } catch {
                // Registered but not answering — launchd refuses to spawn an
                // unnotarized binary, for one. Fall through to asking for a
                // password rather than silently doing nothing.
                helperHandledIt = false
            }
        }
        if !helperHandledIt {
            if !auth.isUnlocked {
                do {
                    try auth.unlock()
                } catch PowerAuthorization.Failure.cancelled {
                    return .cancelled
                } catch {
                    return .failed
                }
            }
            do {
                try auth.run(change)
            } catch {
                outcome = .failed
            }
        }
        let verifiedSettings = await refresh()
        // Neither path can report the tool's exit status, so ask the system
        // whether it agrees rather than assuming a launch meant a change.
        if outcome == .applied, !change.isReflected(in: verifiedSettings) {
            outcome = .failed
        }
        return outcome
    }
}
