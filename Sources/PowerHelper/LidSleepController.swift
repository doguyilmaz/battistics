import BattisticsCore
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
            timer.schedule(deadline: .distantFuture)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                _ = self.lease.expire()
                self.scheduleExpiry()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func acquire(owner: UUID, session: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in
            guard !recoveryFailed else { reply(LidSleepLeaseResult.unavailable.rawValue); return }
            let result = lease.acquire(owner: owner, session: session)
            scheduleExpiry()
            reply(result.rawValue)
        }
    }

    func renew(owner: UUID, session: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in
            let result = lease.renew(owner: owner, session: session)
            scheduleExpiry()
            reply(result.rawValue)
        }
    }

    func release(owner: UUID, session: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in
            let result = lease.release(owner: owner, session: session)
            scheduleExpiry()
            reply(result.rawValue)
        }
    }

    func disconnected(owner: UUID) {
        queue.async { [self] in
            _ = lease.disconnected(owner: owner)
            scheduleExpiry()
        }
    }

    private func scheduleExpiry() {
        guard let deadline = lease.expirationDate else {
            timer?.schedule(deadline: .distantFuture)
            return
        }
        // Lease dates use wall time; use the same clock for the one-shot so
        // a clock correction cannot leave an already-expired lease waiting.
        timer?.schedule(wallDeadline: .now() + max(0, deadline.timeIntervalSinceNow),
                        leeway: .milliseconds(250))
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
        let data = try BoundedCommand.runSynchronously(
            executable: "/usr/bin/pmset", arguments: arguments,
            timeout: 5, maximumOutputBytes: 16_384)
        return String(decoding: data, as: UTF8.self)
    }
}
