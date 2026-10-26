import BattisticsCore
import Foundation
import Observation
import Security

/// Holds one admin authorization so the padlock means something: unlock once,
/// then change settings freely until it relocks.
///
/// Setting power preferences needs root: `IOPMSetPMPreferences` is private
/// *and* privileged, and `pmset` refuses without it. The power helper handles
/// changes when it is installed; this is the fallback for Macs without it,
/// holding the capability in memory so nothing is installed and it dies with
/// the process.
@MainActor
@Observable
final class PowerAuthorization {
    /// Relocks after this long without a change, so a session left open all
    /// day is not a session holding root all day. It only ever expires while
    /// idle, so it costs no prompt anyone would otherwise have avoided.
    static let idleTimeout: Duration = .seconds(600)

    enum Failure: Error, Equatable {
        case cancelled
        /// The deprecated execution path is gone from this macOS.
        case unsupported
        case locked
        case busy
        case failed(OSStatus)
    }

    private(set) var isUnlocked = false

    @ObservationIgnored private var authorization: PowerAuthorizationSession?
    // Retain this even after relocking: an uninterruptible security call
    // must not allow another unlock to accumulate another blocked worker.
    @ObservationIgnored private var pendingAuthorization: PowerAuthorizationSession?
    @ObservationIgnored private var isUnlocking = false
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    /// Whether privileged changes are possible at all on this system.
    var isSupported: Bool { PowerAuthorizationSession.isSupported }

    // MARK: - Lock state

    func unlock() async throws {
        guard pendingAuthorization == nil, !isUnlocking else { throw Failure.busy }
        guard authorization == nil else {
            startIdleTimer()
            return
        }
        guard isSupported else { throw Failure.unsupported }
        isUnlocking = true
        defer { isUnlocking = false }

        // The password dialog blocks its thread until answered; keep it off
        // the main actor so the menu bar and windows stay responsive.
        let (status, address) = await Task.detached { () -> (OSStatus, UInt) in
            var reference: AuthorizationRef?
            guard AuthorizationCreate(nil, nil, [], &reference) == errAuthorizationSuccess,
                let reference
            else { return (errAuthorizationInternal, 0) }
            // Both the name buffer and the item have to outlive the call, so
            // they are nested inside closures that keep them alive rather than
            // passed as `&`-expressions whose lifetime ends at the argument.
            let status = kAuthorizationRightExecute.withCString { name in
                var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                return withUnsafeMutablePointer(to: &item) { items in
                    var rights = AuthorizationRights(count: 1, items: items)
                    return AuthorizationCopyRights(
                        reference, &rights, nil,
                        [.interactionAllowed, .preAuthorize, .extendRights], nil)
                }
            }
            if status != errAuthorizationSuccess { AuthorizationFree(reference, []) }
            return (status, UInt(bitPattern: reference))
        }.value

        guard status == errAuthorizationSuccess,
              let reference = AuthorizationRef(bitPattern: address) else {
            throw status == errAuthorizationCanceled ? Failure.cancelled : Failure.failed(status)
        }
        authorization = PowerAuthorizationSession(takingOwnershipOf: reference)
        isUnlocked = true
        startIdleTimer()
    }

    func relock() {
        idleTask?.cancel()
        idleTask = nil
        // Prevent further use immediately; the session defers destruction
        // only while the worker still holds an in-flight reference.
        authorization?.invalidate()
        authorization = nil
        isUnlocked = false
    }

    private func startIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.relock()
        }
    }

    // MARK: - Running

    func run(_ change: PowerChange) async throws {
        guard pendingAuthorization == nil else { throw Failure.busy }
        guard let authorization else { throw Failure.locked }
        pendingAuthorization = authorization
        idleTask?.cancel()
        idleTask = nil
        defer {
            pendingAuthorization = nil
            if self.authorization === authorization { startIdleTimer() }
        }
        try await authorization.run(change)
    }
}
