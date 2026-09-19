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

    /// Time the registry dictionary was read, not a hardware sample timestamp.
    /// A recent read does not prove that the controller refreshed its values.
    public private(set) var readAt: Date
    /// AppleSmartBattery's reported registry dictionary update time. This is
    /// not a confirmed hardware sample timestamp for PowerTelemetryData.
    public let registryUpdatedAt: Date?
    public let inputWatts: Double?
    public let systemLoadWatts: Double?
    /// Positive into the battery, negative out of it. A concrete contradiction
    /// with the separately reported charging state/current suppresses this value.
    public let batteryPowerWatts: Double?
    public let batteryDirection: BatteryDirection
    /// At least one reported value contradicts the supported interpretation.
    /// Missing context alone does not imply inconsistent readings.
    public let hasInconsistentReadings: Bool

    public var source: String { "AppleSmartBattery.PowerTelemetryData" }

    /// Parses only the dictionary already obtained by BatteryReader.
    /// Missing fields stay unknown; adapter ratings and arithmetic differences
    /// never substitute for a measurement.
    public static func parse(from props: [String: Any], readAt: Date) -> Self? {
        guard let data = props["PowerTelemetryData"] as? [String: Any] else { return nil }
        let reportedBatteryPower = watts(data["BatteryPower"], permitsNegative: true)
        let batteryConflict = contradictsBatteryState(reportedBatteryPower, props: props)
        let batteryPower = batteryConflict ? nil : reportedBatteryPower
        let negativeSystemLoad = integer(data["SystemLoad"]).map { $0 < 0 } ?? false
        return Self(
            readAt: readAt,
            registryUpdatedAt: registryUpdateDate(props["UpdateTime"], readAt: readAt),
            inputWatts: watts(data["SystemPowerIn"], permitsNegative: false),
            systemLoadWatts: watts(data["SystemLoad"], permitsNegative: false),
            batteryPowerWatts: batteryPower,
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
        let normalized: Double?
        if permitsNegative, let number = raw as? NSNumber,
            String(cString: number.objCType) == "Q", number.uint64Value > UInt64(Int64.max) {
            // IORegistry can bridge negative battery power as unsigned 64-bit.
            // Decode before converting to Double, which loses low bits here.
            // The all-ones sentinel is deliberately left unknown in this PoC.
            guard number.uint64Value != UInt64.max else { return nil }
            normalized = Double(Int64(bitPattern: number.uint64Value))
        } else {
            normalized = integer(raw)
        }
        guard let milliwatts = normalized,
            // A bounded PoC range rejects wrapped integers and sentinel values.
            abs(milliwatts) <= 1_000_000,
            permitsNegative || milliwatts >= 0
        else { return nil }
        return milliwatts / 1_000
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
            let charging = boolean(props["IsCharging"]),
            let external = boolean(props["ExternalConnected"]),
            let current = signedCurrent(props["Amperage"])
        else { return .unknown }

        if batteryWatts > 0, current > 0, charging, external { return .charging }
        if batteryWatts < 0, current < 0, !charging { return .discharging }
        if batteryWatts == 0, current == 0, !charging { return .idle }
        return .unknown
    }

    private static func contradictsBatteryState(_ watts: Double?, props: [String: Any]) -> Bool {
        guard let watts else { return false }
        let charging = boolean(props["IsCharging"])
        let external = boolean(props["ExternalConnected"])
        let current = signedCurrent(props["Amperage"])
        if watts > 0 {
            return charging == false || external == false || current.map { $0 < 0 } == true
        }
        if watts < 0 {
            return charging == true || current.map { $0 > 0 } == true
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
}
