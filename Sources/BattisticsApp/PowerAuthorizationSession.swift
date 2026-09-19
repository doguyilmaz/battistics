import BattisticsCore
import Darwin
import Foundation
import Security

/// Owns one authorized reference, including any invocation using it.
/// Revocation and invocation reservation share a lock; the blocking security
/// API and communication reads run only on the owned worker queue.
final class PowerAuthorizationSession: @unchecked Sendable {
    enum Failure: Error {
        case locked
        case busy
        case unsupported
        case failed(OSStatus)
        case timedOut
        case outputLimitExceeded
        case communicationFailed(Int32)
    }

    private let reference: AuthorizationRef
    private let queue = DispatchQueue(label: "app.battistics.authorization", qos: .utility)
    // relock() can run on main while the worker uses the reference. These
    // three fields decide who releases it, exactly once, after its last use.
    private let lock = NSLock()
    private var revoked = false
    private var running = false
    private var released = false

    init(takingOwnershipOf reference: AuthorizationRef) {
        self.reference = reference
    }

    deinit { invalidate() }

    static var isSupported: Bool { executeWithPrivileges != nil }

    func invalidate() {
        let shouldRelease = lock.withLock {
            revoked = true
            guard !running, !released else { return false }
            released = true
            return true
        }
        if shouldRelease { AuthorizationFree(reference, [.destroyRights]) }
    }

    /// Cancellation before reservation prevents launch. Once reserved, the
    /// call finishes or the communication read times out: this deprecated
    /// API provides no child PID with which to cancel privileged execution.
    func run(_ change: PowerChange) async throws {
        try Task.checkCancellation()
        try reserveInvocation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let result = Result { try self.invoke(change) }
                self.finishInvocation()
                continuation.resume(with: result)
            }
        }
    }

    private func reserveInvocation() throws {
        try lock.withLock {
            guard !revoked, !released else { throw Failure.locked }
            guard !running else { throw Failure.busy }
            running = true
        }
    }

    private func finishInvocation() {
        let shouldRelease = lock.withLock {
            running = false
            guard revoked, !released else { return false }
            released = true
            return true
        }
        if shouldRelease { AuthorizationFree(reference, [.destroyRights]) }
    }

    private func invoke(_ change: PowerChange) throws {
        // A relock between reservation and queue dispatch prevents launch.
        guard !lock.withLock({ revoked }) else { throw Failure.locked }
        guard let execute = Self.executeWithPrivileges else { throw Failure.unsupported }
        var argv: [UnsafeMutablePointer<CChar>?] = change.arguments.map { strdup($0) }
        defer { for pointer in argv { free(pointer) } }
        guard argv.allSatisfy({ $0 != nil }) else { throw Failure.failed(errAuthorizationInternal) }
        argv.append(nil)

        var communications: UnsafeMutablePointer<FILE>?
        let status = argv.withUnsafeMutableBufferPointer { buffer in
            execute(reference, PowerSettingsWriter.executable, [], buffer.baseAddress!, &communications)
        }
        defer { if let communications { fclose(communications) } }
        guard status == errAuthorizationSuccess else { throw Failure.failed(status) }
        guard let communications else { throw Failure.communicationFailed(EBADF) }
        try drain(communications)
    }

    private func drain(_ communications: UnsafeMutablePointer<FILE>) throws {
        let descriptor = fileno(communications)
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw Failure.communicationFailed(errno)
        }
        // Output content is discarded, so drain the descriptor in capped
        // chunks. Any bytes already buffered by stdio are discarded at
        // fclose as well; pmset normally emits nothing.
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var bytesRead = 0
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw Failure.timedOut }
            let remainingMilliseconds = Int32((deadline - now + 999_999) / 1_000_000)
            var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptorState, 1, remainingMilliseconds)
            guard ready != 0 else { throw Failure.timedOut }
            if ready < 0 {
                if errno == EINTR { continue } // Recompute the deadline on retry.
                throw Failure.communicationFailed(errno)
            }
            guard descriptorState.revents & Int16(POLLNVAL) == 0 else {
                throw Failure.communicationFailed(EBADF)
            }
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { return }
            if count > 0 {
                bytesRead += count
                guard bytesRead <= 65_536 else { throw Failure.outputLimitExceeded }
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // HUP/ERR are immediately ready again; do not spin if the
                // descriptor can no longer provide either bytes or EOF.
                guard descriptorState.revents & Int16(POLLHUP | POLLERR) == 0 else {
                    throw Failure.communicationFailed(EIO)
                }
            } else {
                throw Failure.communicationFailed(errno)
            }
        }
    }

    /// Runtime lookup preserves the read-only fallback if Apple removes the
    /// deprecated API. Only the fixed pmset path and enum-built argv use it.
    private typealias ExecuteWithPrivileges = @convention(c) @Sendable (
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
