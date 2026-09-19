import BattisticsCore
import Darwin
import Foundation
import IOKit

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
                read: { try Self.readSleepDisabled() },
                write: { _ = try Self.pmset(["-a", "disablesleep", $0 ? "1" : "0"]) },
                save: { [journal] record in
                    try record.encoded().write(to: journal, options: .atomic)
                },
                clear: { [journal] in
                    do { try FileManager.default.removeItem(at: journal) }
                    catch CocoaError.fileNoSuchFile { }
                })
            if FileManager.default.fileExists(atPath: journal.path) {
                do {
                    let record = try LidSleepLeaseJournal.decode(Data(contentsOf: journal))
                    // The lease itself blocks new acquisition if it cannot
                    // durably retire a record. A safely retired transient read
                    // failure must not prohibit a later explicit user session.
                    _ = lease.recover(journal: record)
                } catch { recoveryFailed = true }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in
                // No settings polling, subprocesses, or recovery retries while idle.
                _ = self?.lease.expire()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func acquire(owner: UUID, session: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in
            guard !recoveryFailed else { reply(LidSleepLeaseResult.unavailable.rawValue); return }
            reply(lease.acquire(owner: owner, session: session).rawValue)
        }
    }

    func renew(owner: UUID, session: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in reply(lease.renew(owner: owner, session: session).rawValue) }
    }

    func release(owner: UUID, session: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in reply(lease.release(owner: owner, session: session).rawValue) }
    }

    func disconnected(owner: UUID) {
        queue.async { [self] in _ = lease.disconnected(owner: owner) }
    }

    /// The same root-domain property exported by pmset, without spawning a
    /// process on every heartbeat. Absent or malformed values remain unknown.
    private static func readSleepDisabled() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { throw CocoaError(.fileReadUnknown) }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            throw CocoaError(.fileReadUnknown)
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            let number = value as! CFNumber
            var integer: Int64 = 0
            guard !CFNumberIsFloatType(number), CFNumberGetValue(number, .sInt64Type, &integer),
                  integer == 0 || integer == 1 else { throw CocoaError(.fileReadCorruptFile) }
            return integer == 1
        }
        throw CocoaError(.fileReadCorruptFile)
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
