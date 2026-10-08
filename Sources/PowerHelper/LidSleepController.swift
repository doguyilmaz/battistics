import BattisticsCore
import Foundation
import IOKit
import IOKit.pwr_mgt

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
                write: { [self] disabled in
                    _ = try Self.pmset(["-a", "disablesleep", disabled ? "1" : "0"])
                    Self.waitUntilApplied(disabled)
                    // Queued, so it runs after the lease has verified the
                    // write and dropped its session.
                    if !disabled { queue.async { self.sleepIfLidClosed(attempt: 0) } }
                },
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

    /// Turning sleep back on does not make the kernel look at the lid again:
    /// it evaluates clamshell sleep on lid and power events, and a sleep it
    /// refused while the override was on is never retried. Without this, a
    /// session that ends with the lid shut leaves the Mac running in the bag
    /// until the battery dies. Asks for the sleep the lid would have caused,
    /// and only when the kernel says the lid wants it, so clamshell use with
    /// an external display and power is left alone.
    private func sleepIfLidClosed(attempt: Int) {
        // A session acquired since then owns the lid again.
        guard lease.expirationDate == nil, Self.lidClosedWantsSleep(),
              (try? Self.readSleepDisabled()) == false else { return }
        // Refused while powerd is still applying the setting. Retry briefly
        // rather than leave the Mac awake on a race.
        guard Self.requestSleep() == Self.notPermitted, attempt < 10 else { return }
        queue.asyncAfter(deadline: .now() + .milliseconds(500)) { [self] in
            sleepIfLidClosed(attempt: attempt + 1)
        }
    }

    /// pmset stores the setting and returns; powerd hands it to the kernel a
    /// moment later. The lease reads back right after writing and would take
    /// the old value for someone else's change, so give powerd up to two
    /// seconds to catch up before it looks.
    private static func waitUntilApplied(_ disabled: Bool) {
        for _ in 0..<40 {
            if (try? readSleepDisabled()) == disabled { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// `kIOReturnNotPermitted`, which Swift cannot import: it is built from
    /// function-like macros.
    private static let notPermitted = IOReturn(bitPattern: 0xE000_02E2)

    private static func lidClosedWantsSleep() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        func flag(_ key: String) -> Bool {
            let value = IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
            return (value as? Bool) == true
        }
        // CausesSleep is false in clamshell mode with a display and power.
        return flag("AppleClamshellState") && flag("AppleClamshellCausesSleep")
    }

    private static func requestSleep() -> IOReturn? {
        let connection = IOPMFindPowerManagement(kIOMainPortDefault)
        guard connection != IO_OBJECT_NULL else { return nil }
        defer { IOServiceClose(connection) }
        return IOPMSleepSystem(connection)
    }

    /// The root-domain property pmset sets, read without spawning a process
    /// on every heartbeat. The kernel only publishes it once something has
    /// set it since boot, so when it is absent this asks pmset, which reports
    /// powerd's copy. Absent from both means it was never set: sleep is on.
    private static func readSleepDisabled() throws -> Bool {
        if let value = try registrySleepDisabled() { return value }
        let output = try pmset(["-g"])
        if let value = PowerSettingsReader.sleepDisabled(in: output) { return value }
        guard !output.contains("SleepDisabled") else { throw CocoaError(.fileReadCorruptFile) }
        return false
    }

    private static func registrySleepDisabled() throws -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { throw CocoaError(.fileReadUnknown) }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
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
