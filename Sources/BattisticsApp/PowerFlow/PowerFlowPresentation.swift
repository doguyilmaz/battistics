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

    static var batteryEstimateExplanation: String {
        String(localized: "Battery telemetry is inconsistent. This estimate uses battery voltage × current, the same calculation as the popover’s Power reading. Input and System are not estimated.")
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
        case .idle: String(localized: "No reported flow")
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
