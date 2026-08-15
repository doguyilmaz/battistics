import BattisticsCore
import Foundation
import Observation
import Security

/// Holds one admin authorization so the padlock means something: unlock once,
/// then change settings freely until it relocks.
///
/// Setting power preferences needs root — `IOPMSetPMPreferences` is private
/// *and* privileged, and `pmset` refuses without it. The alternative is an
/// `SMAppService` daemon, which buys the same convenience with a permanently
/// running root process and an XPC surface to keep airtight forever. This
/// keeps the capability in memory instead: nothing is installed, and it dies
/// with the process.
@MainActor
@Observable
final class PowerAuthorization {
    /// Relocks after this long without a change, so a session left open all
    /// day is not a session holding root all day. It only ever expires while
    /// idle, so it costs no prompt anyone would otherwise have avoided.
    static let idleTimeout: Duration = .seconds(600)

    private static let tool = PowerSettingsWriter.executable

    enum Failure: Error, Equatable {
        case cancelled
        /// The deprecated execution path is gone from this macOS.
        case unsupported
        case locked
        case failed(OSStatus)
    }

    private(set) var isUnlocked = false

    @ObservationIgnored private var authorization: AuthorizationRef?
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    /// Whether privileged changes are possible at all on this system. False
    /// means the UI should stay read-only rather than offer a lock that
    /// cannot open.
    var isSupported: Bool { Self.executeWithPrivileges != nil }

    // MARK: - Lock state

    func unlock() throws {
        guard authorization == nil else {
            startIdleTimer()
            return
        }
        guard isSupported else { throw Failure.unsupported }

        var reference: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &reference) == errAuthorizationSuccess,
            let reference
        else { throw Failure.failed(errAuthorizationInternal) }

        // Both the name buffer and the item have to outlive the call, so they
        // are nested inside closures that keep them alive rather than passed
        // as `&`-expressions whose lifetime ends at the argument.
        let status = kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { items in
                var rights = AuthorizationRights(count: 1, items: items)
                return AuthorizationCopyRights(
                    reference, &rights, nil,
                    [.interactionAllowed, .preAuthorize, .extendRights], nil)
            }
        }

        guard status == errAuthorizationSuccess else {
            AuthorizationFree(reference, [])
            throw status == errAuthorizationCanceled ? Failure.cancelled : Failure.failed(status)
        }
        authorization = reference
        isUnlocked = true
        startIdleTimer()
    }

    func relock() {
        idleTask?.cancel()
        idleTask = nil
        if let authorization {
            // destroyRights so the credential does not outlive the lock.
            AuthorizationFree(authorization, [.destroyRights])
        }
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

    func run(_ arguments: [String]) throws {
        guard let authorization else { throw Failure.locked }
        guard let execute = Self.executeWithPrivileges else { throw Failure.unsupported }

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        defer { for pointer in argv where pointer != nil { free(pointer) } }

        var communications: UnsafeMutablePointer<FILE>?
        let status = argv.withUnsafeMutableBufferPointer { buffer in
            execute(authorization, Self.tool, [], buffer.baseAddress!, &communications)
        }
        // Draining to EOF waits for the child to exit, so the caller can
        // re-read the settings and see the result rather than a race.
        if let communications {
            while fgetc(communications) != EOF {}
            fclose(communications)
        }
        guard status == errAuthorizationSuccess else { throw Failure.failed(status) }
        startIdleTimer()
    }

    /// Resolved at runtime rather than called directly.
    ///
    /// `AuthorizationExecuteWithPrivileges` has been deprecated since macOS
    /// 10.7 and still ships, but looking it up through `dlsym` means the day
    /// Apple finally removes it this returns nil and the UI degrades to
    /// read-only, instead of the app failing to launch. It also keeps the
    /// build free of a deprecation warning that could not otherwise be
    /// silenced at the call site.
    ///
    /// Apple's stated objection is that the executed path is unvalidated.
    /// Here it is a hardcoded `/usr/bin/pmset` and every argument comes from
    /// a fixed enum in `PowerSettingsWriter`, so nothing a user types reaches
    /// it.
    private typealias ExecuteWithPrivileges = @convention(c) (
        AuthorizationRef,
        UnsafePointer<CChar>,
        AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>?>,
        UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private static let executeWithPrivileges: ExecuteWithPrivileges? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
            "AuthorizationExecuteWithPrivileges")
        else { return nil }
        return unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)
    }()
}
