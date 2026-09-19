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

    func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", abs(value))
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
