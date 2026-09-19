import CoreFoundation
import Foundation

/// Experimental, read-only values reported by the smart battery controller.
/// These private registry fields can be absent or change between Mac models.
public struct PowerFlowTelemetry: Sendable, Equatable {
    public enum BatteryDirection: Sendable {
        case charging
        case discharging
        case idle
        case unknown
    }

    public enum BatteryPowerSource: Sendable {
        case reported
        case estimatedFromVoltageAndCurrent
    }

    public enum SystemPowerSource: Sendable {
        case reported
        case estimatedFromInputAndBattery
    }

    /// Time the registry dictionary was read, not a hardware sample timestamp.
    /// A recent read does not prove that the controller refreshed its values.
    public private(set) var readAt: Date
    /// AppleSmartBattery's reported registry dictionary update time. This is
    /// not a confirmed hardware sample timestamp for PowerTelemetryData.
    public let registryUpdatedAt: Date?
    public let inputWatts: Double?
    /// Selected system reading. When direct accounting is unavailable or conflicts,
    /// a labeled estimate can use input minus signed selected battery power.
    public let systemLoadWatts: Double?
    public let systemPowerSource: SystemPowerSource?
    /// Positive into the battery, negative out of it. Conflicting direct readings
    /// use a validated voltage × current estimate when available; inspect source.
    public let batteryPowerWatts: Double?
    public let batteryPowerSource: BatteryPowerSource?
    public let batteryDirection: BatteryDirection
    /// At least one reported value contradicts the supported interpretation.
    /// Missing context alone does not imply inconsistent readings.
    public let hasInconsistentReadings: Bool

    public var source: String { "AppleSmartBattery.PowerTelemetryData" }

    /// Parses only the dictionary already obtained by BatteryReader.
    /// Estimates are explicitly sourced; adapter ratings never substitute for
    /// measured input and missing operands never become assumed zeros.
    public static func parse(from props: [String: Any], readAt: Date) -> Self? {
        guard let data = props["PowerTelemetryData"] as? [String: Any] else { return nil }
        let reportedBatteryPower = watts(data["BatteryPower"], permitsNegative: true)
        let batteryConflict = contradictsBatteryState(reportedBatteryPower, props: props)
        let batteryPower = batteryConflict ? estimatedBatteryPower(from: props) : reportedBatteryPower
        let batterySource: BatteryPowerSource? = batteryPower == nil ? nil
            : (batteryConflict ? .estimatedFromVoltageAndCurrent : .reported)
        let negativeSystemLoad = signedTelemetryInteger(data["SystemLoad"]).map { $0 < 0 } ?? false
        let inputPower = watts(data["SystemPowerIn"], permitsNegative: false)
        let reportedSystemPower = batteryConflict ? nil : watts(data["SystemLoad"], permitsNegative: false)
        let systemPower = reportedSystemPower ?? estimatedSystemPower(input: inputPower, battery: batteryPower)
        let systemSource: SystemPowerSource? = systemPower == nil ? nil
            : (reportedSystemPower != nil ? .reported : .estimatedFromInputAndBattery)
        return Self(
            readAt: readAt,
            registryUpdatedAt: registryUpdateDate(props["UpdateTime"], readAt: readAt),
            inputWatts: inputPower,
            systemLoadWatts: systemPower,
            systemPowerSource: systemSource,
            batteryPowerWatts: batteryPower,
            batteryPowerSource: batterySource,
            batteryDirection: direction(from: props, batteryWatts: batteryPower),
            hasInconsistentReadings: negativeSystemLoad || batteryConflict
        )
    }

    public func isStale(at now: Date, maximumAge: TimeInterval = 30) -> Bool {
        let age = now.timeIntervalSince(readAt)
        guard age.isFinite, maximumAge.isFinite, maximumAge >= 0 else { return true }
        // Clock changes cannot make a future-dated read indefinitely fresh.
        return age < 0 || age > maximumAge
    }

    public func hasSameReadings(as other: Self) -> Bool {
        var reading = self
        // Source metadata changes remain observable even if watts stay equal.
        reading.readAt = other.readAt
        return reading == other
    }

    private static func registryUpdateDate(_ raw: Any?, readAt: Date) -> Date? {
        guard let number = raw as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let seconds = number.doubleValue
        let readSeconds = readAt.timeIntervalSince1970
        // Reject implausible epochs while allowing a small clock skew.
        guard seconds.isFinite, readSeconds.isFinite,
            seconds >= 946_684_800, seconds <= readSeconds + 5
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func watts(_ raw: Any?, permitsNegative: Bool) -> Double? {
        guard let milliwatts = signedTelemetryInteger(raw),
            // A bounded PoC range rejects wrapped integers and sentinel values.
            abs(milliwatts) <= 1_000_000,
            permitsNegative || milliwatts >= 0
        else { return nil }
        return milliwatts / 1_000
    }

    private static func signedTelemetryInteger(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber,
            String(cString: number.objCType) == "Q", number.uint64Value > UInt64(Int64.max) {
            // IORegistry can bridge negative telemetry as unsigned 64-bit.
            // Decode before converting to Double, which loses low bits here.
            // The all-ones sentinel is deliberately left unknown in this PoC.
            guard number.uint64Value != UInt64.max else { return nil }
            return Double(Int64(bitPattern: number.uint64Value))
        }
        return integer(raw)
    }

    private static func integer(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded(.towardZero) == value else { return nil }
        return value
    }

    private static func boolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return nil }
        return number.boolValue
    }

    private static func direction(from props: [String: Any], batteryWatts: Double?) -> BatteryDirection {
        guard let batteryWatts,
            let external = boolean(props["ExternalConnected"]),
            let current = signedCurrent(props["Amperage"])
        else { return .unknown }

        // This label follows the selected power reading. A separately sampled
        // zero current does not contradict it or independently corroborate it.
        // IsCharging can remain true while the battery supports a connected Mac.
        if batteryWatts > 0, current >= 0, external { return .charging }
        if batteryWatts < 0, current <= 0 { return .discharging }
        if batteryWatts == 0, current == 0 { return .idle }
        return .unknown
    }

    private static func contradictsBatteryState(_ watts: Double?, props: [String: Any]) -> Bool {
        guard let watts else { return false }
        let external = boolean(props["ExternalConnected"])
        let current = signedCurrent(props["Amperage"])
        if watts > 0 {
            return external == false || current.map { $0 < 0 } == true
        }
        if watts < 0 {
            return current.map { $0 > 0 } == true
        }
        // A rounded zero and separately sampled current need not agree exactly.
        return false
    }

    private static func signedCurrent(_ raw: Any?) -> Int? {
        guard let rawCurrent = integer(raw),
            rawCurrent >= Double(Int32.min), rawCurrent <= Double(UInt32.max),
            let current = BatteryReader.signedMilliamps(Int(rawCurrent)),
            // Do not interpret unrealistic or sentinel current as a direction.
            abs(current) <= 100_000
        else { return nil }
        return current
    }

    private static func estimatedBatteryPower(from props: [String: Any]) -> Double? {
        guard let voltage = integer(props["Voltage"]),
            // Broad laptop battery bounds exclude sentinels and implausible input.
            (1_000...30_000).contains(voltage),
            let current = signedCurrent(props["Amperage"]),
            let estimate = BatterySnapshot.powerWatts(voltageMV: Int(voltage), amperageMA: current),
            estimate.isFinite, abs(estimate) <= 1_000,
            !contradictsBatteryState(estimate, props: props)
        else { return nil }
        return estimate
    }

    private static func estimatedSystemPower(input: Double?, battery: Double?) -> Double? {
        guard let input, let battery else { return nil }
        let estimate = input - battery
        guard estimate.isFinite, (0...1_000).contains(estimate) else { return nil }
        return estimate
    }
}
