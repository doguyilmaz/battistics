import Foundation
import IOKit
import IOKit.ps

/// Reads the smart battery controller from the IORegistry. `read()` touches
/// IOKit; `snapshot(from:iops:now:)` is pure and unit-testable with a plain
/// dictionary captured from `ioreg -rn AppleSmartBattery`.
public enum BatteryReader {
    public struct SystemPowerInfo: Sendable {
        public let healthStatus: String?
        public let timeRemainingMin: Int?

        public init(healthStatus: String?, timeRemainingMin: Int?) {
            self.healthStatus = healthStatus
            self.timeRemainingMin = timeRemainingMin
        }
    }

    public static func read(now: Date = Date()) -> BatterySnapshot? {
        guard let props = smartBatteryProperties() else { return nil }
        return snapshot(from: props, iops: systemPowerInfo(), now: now)
    }

    public static func snapshot(from props: [String: Any], iops: SystemPowerInfo?, now: Date) -> BatterySnapshot {
        func int(_ key: String) -> Int? { props[key] as? Int }
        func bool(_ key: String) -> Bool? { props[key] as? Bool }

        let maxCapacityKey = int("MaxCapacity") ?? 100
        let currentCapacityKey = int("CurrentCapacity") ?? 0
        let rawCurrent = int("AppleRawCurrentCapacity") ?? currentCapacityKey
        let rawMax = int("AppleRawMaxCapacity") ?? maxCapacityKey
        let design = int("DesignCapacity") ?? 0

        // Apple Silicon normalizes CurrentCapacity/MaxCapacity to a 0-100 scale.
        let percent: Int
        if maxCapacityKey == 100 {
            percent = min(max(currentCapacityKey, 0), 100)
        } else if rawMax > 0 {
            percent = Int((Double(rawCurrent) / Double(rawMax) * 100).rounded())
        } else {
            percent = 0
        }

        // VirtualTemperature is the modeled value macOS bases thermal
        // decisions on and what users compare against; the raw cell sensor
        // (Temperature) is kept as a secondary reading.
        let cellTemperature = int("Temperature").map { Double($0) / 100 }
        let virtualTemperature = int("VirtualTemperature").map { Double($0) / 100 }
        let temperature = virtualTemperature ?? cellTemperature

        var adapter: AdapterInfo?
        if let details = props["AdapterDetails"] as? [String: Any] {
            let watts = details["Watts"] as? Int
            let name = (details["Name"] as? String) ?? (details["Description"] as? String)
            let voltage = details["AdapterVoltage"] as? Int
            let current = details["Current"] as? Int
            if watts != nil || name != nil {
                adapter = AdapterInfo(name: name, watts: watts, voltageMV: voltage, amperageMA: current)
            }
        }

        // Some controllers pack the date SMBus style (16 bits); Apple
        // Silicon packs report opaque blobs there, in which case the serial
        // number's week code is the reliable source.
        var manufactureDate: Date?
        if let packed = int("ManufactureDate"), packed <= 0xFFFF {
            manufactureDate = Self.manufactureDate(fromSMBus: packed)
        }
        if manufactureDate == nil,
            let batteryData = props["BatteryData"] as? [String: Any],
            let packed = batteryData["ManufactureDate"] as? Int, packed <= 0xFFFF {
            manufactureDate = Self.manufactureDate(fromSMBus: packed)
        }
        if manufactureDate == nil, let serial = props["Serial"] as? String {
            manufactureDate = Self.manufactureDate(fromSerial: serial, now: now)
        }

        return BatterySnapshot(
            timestamp: now,
            batteryInstalled: bool("BatteryInstalled") ?? true,
            percent: percent,
            rawCurrentCapacity: rawCurrent,
            rawMaxCapacity: rawMax,
            nominalCapacity: int("NominalChargeCapacity"),
            designCapacity: design,
            cycleCount: int("CycleCount") ?? 0,
            designCycleCount: int("DesignCycleCount9C"),
            temperatureC: temperature,
            cellTemperatureC: cellTemperature,
            voltageMV: int("Voltage"),
            amperageMA: signedMilliamps(int("Amperage")),
            isCharging: bool("IsCharging") ?? false,
            externalConnected: bool("ExternalConnected") ?? false,
            fullyCharged: bool("FullyCharged") ?? false,
            avgTimeToEmptyMin: int("AvgTimeToEmpty"),
            avgTimeToFullMin: int("AvgTimeToFull"),
            systemTimeRemainingMin: iops?.timeRemainingMin,
            systemHealthStatus: iops?.healthStatus,
            serialNumber: props["Serial"] as? String,
            deviceName: props["DeviceName"] as? String,
            manufactureDate: manufactureDate,
            adapter: adapter
        )
    }

    /// Older controllers report Amperage as a UInt32 in two's complement.
    public static func signedMilliamps(_ raw: Int?) -> Int? {
        guard var value = raw else { return nil }
        if value > Int(Int32.max), value <= Int(UInt32.max) {
            value -= Int(UInt32.max) + 1
        }
        return value
    }

    /// Battery serials encode the manufacture week after a 3 character
    /// site code: one year digit and two week digits
    /// (F8Y 1 49 20... = week 49 of 2021).
    public static func manufactureDate(fromSerial serial: String, now: Date = Date()) -> Date? {
        let chars = Array(serial)
        guard chars.count >= 6,
            let yearDigit = chars[3].wholeNumberValue,
            let weekTens = chars[4].wholeNumberValue,
            let weekOnes = chars[5].wholeNumberValue
        else { return nil }
        let week = weekTens * 10 + weekOnes
        guard (1...53).contains(week) else { return nil }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let currentYear = calendar.component(.yearForWeekOfYear, from: now)
        // The year is a single digit: pick the most recent matching year
        // that does not put the date in the future.
        var year = currentYear - ((currentYear - yearDigit) % 10 + 10) % 10
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 4
        guard var date = calendar.date(from: components) else { return nil }
        if date > now {
            year -= 10
            components.yearForWeekOfYear = year
            guard let earlier = calendar.date(from: components) else { return nil }
            date = earlier
        }
        return date
    }

    /// SMBus packed date: bits 0-4 day, 5-8 month, 9-15 years since 1980.
    public static func manufactureDate(fromSMBus value: Int) -> Date? {
        let day = value & 0x1F
        let month = (value >> 5) & 0x0F
        let year = 1980 + ((value >> 9) & 0x7F)
        guard (2005...2045).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let props = propsRef?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return props
    }

    private static func systemPowerInfo() -> SystemPowerInfo? {
        var health: String?
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] {
                    health = description["BatteryHealth"] as? String
                }
            }
        }
        let seconds = IOPSGetTimeRemainingEstimate()
        let minutes: Int? = seconds > 0 ? Int(seconds / 60) : nil
        return SystemPowerInfo(healthStatus: health, timeRemainingMin: minutes)
    }
}
