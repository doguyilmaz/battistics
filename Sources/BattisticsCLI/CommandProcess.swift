import Darwin
import Foundation

final class CommandProcess: @unchecked Sendable {
    let identifier: pid_t
    private let waitQueue = DispatchQueue(label: "com.doguyilmaz.Battistics.command.wait")

    init(command: [String]) throws {
        let arguments = command.map { strdup($0) } + [nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            arguments.forEach { free($0) }
            environment.forEach { free($0) }
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for number in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&defaults, number) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        var pid: pid_t = 0
        // Inherit the foreground process group so terminal reads and job control work.
        let error = arguments.withUnsafeBufferPointer { argv in
            environment.withUnsafeBufferPointer { env in
                posix_spawnp(&pid, command[0], nil, &attributes, argv.baseAddress!, env.baseAddress!)
            }
        }
        guard error == 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
        identifier = pid
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            waitQueue.async {
                var status: Int32 = 0
                var result: pid_t
                repeat { result = waitpid(self.identifier, &status, 0) } while result < 0 && errno == EINTR
                guard result == self.identifier else { continuation.resume(returning: 70); return }
                let signal = status & 0x7f
                continuation.resume(returning: signal == 0 ? (status >> 8) & 0xff : 128 + signal)
            }
        }
    }
}
