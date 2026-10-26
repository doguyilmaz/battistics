import Foundation
import IOKit

/// The system-wide `SleepDisabled` override that `pmset disablesleep` sets.
/// While it is on the Mac never sleeps, not even with the lid closed, and
/// pmset keeps it across restarts.
public enum SystemSleep {
    /// Puts the Mac to sleep now; needs no privileges, but does nothing while
    /// the override is on.
    public static func now() async throws {
        _ = try await BoundedCommand.run(executable: PowerSettingsWriter.executable, arguments: ["sleepnow"],
                                         timeout: 5, maximumOutputBytes: 16_384)
    }

    /// Reads the root-domain property without spawning a process. The kernel
    /// only publishes it once something has set it since boot, so when it is
    /// absent this asks pmset, which reports powerd's copy. Absent from both
    /// means it was never set: sleep is on.
    public static func isDisabledSynchronously() throws -> Bool {
        if let value = try registryValue() { return value }
        return try parse(BoundedCommand.runSynchronously(
            executable: PowerSettingsWriter.executable, arguments: ["-g"], timeout: 5, maximumOutputBytes: 16_384))
    }

    public static func isDisabled() async throws -> Bool {
        if let value = try registryValue() { return value }
        return try parse(await BoundedCommand.run(
            executable: PowerSettingsWriter.executable, arguments: ["-g"], timeout: 5, maximumOutputBytes: 16_384))
    }

    private static func parse(_ data: Data) throws -> Bool {
        let output = String(decoding: data, as: UTF8.self)
        if let value = PowerSettingsReader.sleepDisabled(in: output) { return value }
        guard !output.contains("SleepDisabled") else { throw CocoaError(.fileReadCorruptFile) }
        return false
    }

    private static func registryValue() throws -> Bool? {
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
}
