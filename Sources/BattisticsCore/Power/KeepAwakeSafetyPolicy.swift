import Foundation

/// Session-scoped protection. Ending an assertion permits normal sleep; it
/// never requests shutdown, force-quits apps, or promises a battery runtime.
public struct KeepAwakeSafetyPolicy: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var stopOnLowBattery: Bool
        public var stopPercent: Int
        public var warnOnLowBattery: Bool
        public var warningPercent: Int
        public var stopOnThermalPressure: Bool

        public init(
            stopOnLowBattery: Bool = false, stopPercent: Int = 10,
            warnOnLowBattery: Bool = true, warningPercent: Int = 20,
            stopOnThermalPressure: Bool = false
        ) {
            self.stopOnLowBattery = stopOnLowBattery
            self.stopPercent = stopPercent
            self.warnOnLowBattery = warnOnLowBattery
            self.warningPercent = warningPercent
            self.stopOnThermalPressure = stopOnThermalPressure
        }

        public var effectiveStopPercent: Int { min(max(stopPercent, 5), 50) }
        public var effectiveWarningPercent: Int {
            max(min(max(warningPercent, 10), 80), stopOnLowBattery ? effectiveStopPercent + 5 : 10)
        }
    }

    public enum Event: Sendable, Equatable {
        case batteryWarning(percent: Int, stopAt: Int?)
        case batteryStop(percent: Int)
        case thermalWarning
        case thermalStop

        public var endsSession: Bool {
            switch self {
            case .batteryStop, .thermalStop: true
            case .batteryWarning, .thermalWarning: false
            }
        }
    }

    private var batteryWarningSent = false
    private var thermalWarningSent = false

    public init() {}

    /// Also used before acquiring a privileged lease. Missing/invalid battery
    /// data must not be interpreted as an empty battery.
    public static func stopReason(
        snapshot: BatterySnapshot?, thermalPressure: Bool, configuration: Configuration
    ) -> Event? {
        if configuration.stopOnLowBattery, let snapshot,
            snapshot.batteryInstalled, !snapshot.externalConnected,
            (0...100).contains(snapshot.percent),
            snapshot.percent <= configuration.effectiveStopPercent {
            return .batteryStop(percent: snapshot.percent)
        }
        if configuration.stopOnThermalPressure, thermalPressure { return .thermalStop }
        return nil
    }

    public mutating func evaluate(
        snapshot: BatterySnapshot?, thermalPressure: Bool, configuration: Configuration
    ) -> [Event] {
        if let stop = Self.stopReason(
            snapshot: snapshot, thermalPressure: thermalPressure, configuration: configuration
        ) { return [stop] }

        var events: [Event] = []
        if let snapshot, snapshot.batteryInstalled, (0...100).contains(snapshot.percent) {
            if snapshot.externalConnected
                || snapshot.percent > configuration.effectiveWarningPercent + 2 {
                batteryWarningSent = false
            } else if configuration.warnOnLowBattery, !snapshot.externalConnected,
                snapshot.percent <= configuration.effectiveWarningPercent, !batteryWarningSent {
                batteryWarningSent = true
                events.append(.batteryWarning(
                    percent: snapshot.percent,
                    stopAt: configuration.stopOnLowBattery ? configuration.effectiveStopPercent : nil))
            }
        }
        if thermalPressure {
            if !thermalWarningSent {
                thermalWarningSent = true
                events.append(.thermalWarning)
            }
        } else {
            thermalWarningSent = false
        }
        return events
    }
}
