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
        let before = Self.childProcesses()
        let status = argv.withUnsafeMutableBufferPointer { buffer in
            execute(reference, PowerSettingsWriter.executable, [], buffer.baseAddress!, &communications)
        }
        let privileged = Self.childProcesses().subtracting(before).filter(Self.runsAsRoot)
        // Runs after the pipe closes, so the child has exited or is about to.
        defer { Self.reap(privileged) }
        defer { if let communications { fclose(communications) } }
        guard status == errAuthorizationSuccess else { throw Failure.failed(status) }
        guard let communications else { throw Failure.communicationFailed(EBADF) }
        try drain(communications)
    }

    /// The API gives no child PID, so the child is found as the new root
    /// process among this app's children; other children run as the user.
    private static func childProcesses() -> Set<pid_t> {
        var pids = [pid_t](repeating: 0, count: 256)
        _ = proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Set(pids.filter { $0 > 0 })
    }

    private static func runsAsRoot(_ pid: pid_t) -> Bool {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        return proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size && info.pbsi_uid == 0
    }

    /// Collects the finished child so it does not stay a zombie until quit.
    private static func reap(_ pids: Set<pid_t>) {
        for pid in pids {
            var status: Int32 = 0
            for _ in 0..<100 {
                if waitpid(pid, &status, WNOHANG) != 0 { break }
                usleep(20_000)
            }
        }
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
