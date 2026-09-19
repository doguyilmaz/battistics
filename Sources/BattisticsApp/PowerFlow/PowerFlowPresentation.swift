import BattisticsCore
import Foundation

/// Presentation of one registry read; unknown values never become fabricated flows.
struct PowerFlowPresentation {
    let telemetry: PowerFlowTelemetry?

    init(snapshot: BatterySnapshot?, lastReadAt: Date?, now: Date = Date()) {
        if let lastReadAt, (0...30).contains(now.timeIntervalSince(lastReadAt)) {
            telemetry = snapshot?.powerFlow
        } else {
            telemetry = nil
        }
    }

    var hasReadings: Bool {
        telemetry?.inputWatts != nil || telemetry?.systemLoadWatts != nil
            || telemetry?.batteryPowerWatts != nil
    }

    var statusText: String {
        if systemIsEstimated && batteryIsEstimated {
            return String(localized: "Estimated readings")
        }
        if systemIsEstimated {
            return String(localized: "System estimated")
        }
        if batteryIsEstimated {
            return String(localized: "Battery estimated")
        }
        if telemetry?.hasInconsistentReadings == true {
            return String(localized: "Readings inconsistent")
        }
        return hasReadings
            ? String(localized: "Readings may lag")
            : String(localized: "Readings unavailable")
    }

    var batteryIsEstimated: Bool {
        telemetry?.batteryPowerSource == .estimatedFromVoltageAndCurrent
    }

    var systemIsEstimated: Bool {
        telemetry?.systemPowerSource == .estimatedFromInputAndBattery
    }

    var systemLabel: String {
        switch telemetry?.systemPowerSource {
        case .reported: String(localized: "Reported load")
        case .estimatedFromInputAndBattery: String(localized: "Estimated load")
        case nil: String(localized: "Load unavailable")
        }
    }

    static var batteryEstimateExplanation: String {
        String(localized: "The reported battery reading is inconsistent. A valid reported reading will replace this estimate automatically.")
    }

    static var systemEstimateExplanation: String {
        String(localized: "The reported system reading is unavailable or inconsistent. A valid reported reading will replace this estimate automatically.")
    }

    func watts(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "—" }
        if abs(value) < 0.05 { return "0.0 W" }
        return String(format: signed ? "%+.1f W" : "%.1f W", signed ? value : abs(value))
    }

    var batteryLabel: String {
        switch telemetry?.batteryDirection {
        case .charging: String(localized: "Charging")
        case .discharging: String(localized: "Discharging")
        case .idle: String(localized: "No flow indicated")
        default: String(localized: "Direction unknown")
        }
    }

    var batteryArrow: String? {
        switch telemetry?.batteryDirection {
        case .charging: "arrow.right"
        case .discharging: "arrow.left"
        default: nil
        }
    }
}
