import BattisticsCore
import Darwin
import Foundation

/// All lease state, file I/O and pmset calls belong to this serial queue.
final class LidSleepController: @unchecked Sendable {
    static let shared = LidSleepController()
    private let queue = DispatchQueue(label: "Battistics.lid-sleep")
    private let journal = URL(fileURLWithPath: "/var/db/com.doguyilmaz.Battistics.lid-sleep")
    private var lease: LidSleepLease!
    private var timer: DispatchSourceTimer?
    private var recoveryFailed = false

    private init() {
        queue.async { [self] in
            lease = LidSleepLease(
                read: {
                    let output = try Self.pmset(["-g"])
                    guard output.contains("System-wide power settings:") else { throw CocoaError(.fileReadCorruptFile) }
                    for line in output.split(separator: "\n") {
                        let fields = line.split(whereSeparator: \.isWhitespace)
                        if fields.first == "SleepDisabled" {
                            guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else {
                                throw CocoaError(.fileReadCorruptFile)
                            }
                            return fields[1] == "1"
                        }
                    }
                    return false
                },
                write: { _ = try Self.pmset(["-a", "disablesleep", $0 ? "1" : "0"]) },
                save: { [journal] original in
                    try Data((original ? "1" : "0").utf8).write(to: journal, options: .atomic)
                },
                clear: { [journal] in try FileManager.default.removeItem(at: journal) })
            if FileManager.default.fileExists(atPath: journal.path) {
                do {
                    try recoverJournal()
                } catch { recoveryFailed = true }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                do {
                    if self.recoveryFailed {
                        try self.recoverJournal()
                        self.recoveryFailed = false
                    } else {
                        try self.lease.expire()
                    }
                } catch {
                    // Retain the journal and retry on the next watchdog tick.
                }
            }
            timer.resume()
            self.timer = timer
        }
    }

    func set(enabled: Bool, owner: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in
            guard !recoveryFailed else { reply(EIO); return }
            do {
                if enabled { try lease.renew(owner: owner) }
                else { try lease.release(owner: owner) }
                reply(0)
            } catch { reply(EIO) }
        }
    }

    func disconnected(owner: UUID) {
        queue.async { [self] in try? lease.release(owner: owner) }
    }

    private func recoverJournal() throws {
        let saved = try String(contentsOf: journal, encoding: .utf8)
        guard saved == "0" || saved == "1" else { throw CocoaError(.fileReadCorruptFile) }
        // A missing/corrupt journal must not turn a no-op expiry into a
        // successful recovery. Clear the failure latch only after restoration.
        try lease.recover(original: saved == "1")
    }

    private static func pmset(_ arguments: [String]) throws -> String {
        // Capture to an unlinked private file: reading a pipe to EOF can block
        // past the process deadline, and a full pipe can prevent process exit.
        var path = FileManager.default.temporaryDirectory
            .appendingPathComponent("Battistics-pmset-XXXXXX").path.utf8CString
        let descriptor = path.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        _ = path.withUnsafeBufferPointer { unlink($0.baseAddress!) }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        guard exited.wait(timeout: .now() + 5) == .success else {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                // Never wait indefinitely on the serial lease/watchdog queue.
                _ = kill(process.processIdentifier, SIGKILL)
            }
            throw POSIXError(.ETIMEDOUT)
        }
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        try output.seek(toOffset: 0)
        let data = try output.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
