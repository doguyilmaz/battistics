import BattisticsRemote
import SwiftUI

extension RemoteStatus.Mode {
    var label: String {
        switch self {
        case .displayMaySleep: String(localized: "Screen Off")
        case .displayOn: String(localized: "Screen On")
        case .lidClosed: String(localized: "Lid Closed")
        }
    }

    var subtitle: String {
        switch self {
        case .displayMaySleep: String(localized: "Mac stays awake, display may sleep")
        case .displayOn: String(localized: "Both Mac and display stay awake")
        case .lidClosed: String(localized: "Stays awake with lid closed in your bag")
        }
    }

    var symbol: String {
        switch self {
        case .displayMaySleep: "moon.fill"
        case .displayOn: "sun.max.fill"
        case .lidClosed: "laptopcomputer"
        }
    }
}

extension RemoteStatus.Origin {
    var label: String {
        switch self {
        case .manual: String(localized: "Started on Mac")
        case .profile: String(localized: "Profile")
        case .terminal: String(localized: "Terminal")
        case .ai: String(localized: "AI task")
        case .phone: String(localized: "Started from iPhone")
        }
    }
}

extension RemoteStatus.EndReason {
    var label: String {
        switch self {
        case .timer: String(localized: "Time ran out")
        case .user: String(localized: "Stopped on Mac")
        case .phone: String(localized: "Stopped from iPhone")
        case .battery: String(localized: "Battery protection")
        case .thermal: String(localized: "Heat protection")
        case .client: String(localized: "Task finished")
        case .failure: String(localized: "macOS ended it")
        }
    }
}

extension RemoteStatus.Network {
    var label: String {
        switch self {
        case .wifi: String(localized: "Wi‑Fi")
        case .hotspot: String(localized: "Hotspot")
        case .wired: String(localized: "Ethernet")
        case .other: String(localized: "Online")
        case .offline: String(localized: "Offline")
        }
    }

    var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .hotspot: "personalhotspot"
        case .wired: "cable.connector"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }
}

extension RemoteStatus {
    /// The Wi‑Fi or Hotspot name, if the Mac could read it.
    func resolvedNetworkName() -> String? {
        guard let name = networkName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
}

extension RemoteStatus {
    var macSymbol: String { battery == nil ? "desktopcomputer" : "laptopcomputer" }

    /// The Mac's symbol, flagged while it is not answering.
    func macSymbol(reachable: Bool) -> String {
        if reachable { return macSymbol }
        return battery == nil ? "desktopcomputer.trianglebadge.exclamationmark" : "laptopcomputer.slash"
    }
}

extension RemoteStatus.Thermal {
    var label: String {
        switch self {
        case .nominal: String(localized: "Normal")
        case .fair: String(localized: "Warm")
        case .serious: String(localized: "Hot")
        case .critical: String(localized: "Critical")
        }
    }

    var tint: Color {
        switch self {
        case .nominal, .fair: .secondary
        case .serious: .orange
        case .critical: .red
        }
    }
}

extension RemoteStatus.LowPowerPolicy {
    var label: String {
        switch self {
        case .never: String(localized: "Never")
        case .onlyOnBattery: String(localized: "Only on Battery")
        case .onlyOnAdapter: String(localized: "Only on Power Adapter")
        case .always: String(localized: "Always")
        }
    }

    var compactBadge: String {
        switch self {
        case .never: String(localized: "Off")
        case .onlyOnBattery: String(localized: "Battery")
        case .onlyOnAdapter: String(localized: "Adapter")
        case .always: String(localized: "Always")
        }
    }

    var symbol: String {
        switch self {
        case .never: "bolt.circle"
        case .onlyOnBattery: "leaf"
        case .onlyOnAdapter: "powerplug"
        case .always: "leaf.fill"
        }
    }
}

extension RemoteStatus.Battery {
    var symbol: String {
        if lowPowerMode == true { return "leaf.fill" }
        if isCharging { return "bolt.fill" }
        if onAdapter { return "powerplug.fill" }
        return "battery.75percent"
    }

    var headline: String {
        if isCharging { return String(localized: "Charging") }
        if onAdapter { return String(localized: "Plugged In") }
        return String(localized: "On Battery")
    }

    /// Signed watts while power flows into or out of the battery.
    var flowText: String? {
        guard let watts, abs(watts) >= 0.5 else { return nil }
        let rounded = Int(watts.rounded())
        return rounded > 0 ? "+\(rounded) W" : "\(rounded) W"
    }

    /// The flow, or the adapter rating while nothing flows.
    var powerText: String? { flowText ?? adapterWatts.map { "\($0) W" } }

    var temperatureText: String? {
        temperatureC.map { $0.formatted(.number.precision(.fractionLength(0))) + " °C" }
    }

    /// "2 hr 10 min left" or "40 min to full", when macOS has an estimate.
    var timeText: String? {
        guard let minutesRemaining else { return nil }
        let time = DurationLabel.long(minutes: minutesRemaining)
        return isCharging ? String(localized: "\(time) to full") : String(localized: "\(time) left")
    }
}

extension Int {
    /// "57%", or "%57" where the locale puts the sign first.
    var percentText: String { (Double(self) / 100).formatted(.percent.precision(.fractionLength(0))) }
}

enum PowerPalette {
    static let charging = Color(red: 0.16, green: 0.80, blue: 0.44)
    static let lowPower = Color(red: 0.95, green: 0.72, blue: 0.08)
    static let hotspot = Color(red: 0.05, green: 0.72, blue: 0.96)

    static func batteryTint(_ battery: RemoteStatus.Battery) -> Color {
        if battery.lowPowerMode == true { return lowPower }
        if battery.isCharging || battery.onAdapter { return charging }
        if battery.percent <= 10 { return .red }
        if battery.percent <= 20 { return .orange }
        return .accentColor
    }
}

enum Ago {
    /// "7 minutes ago", then "1 hour ago": whole units that stay current in
    /// widgets and Live Activities, never seconds.
    static func text(_ date: Date) -> Text {
        if #available(iOS 18, *) {
            Text(.currentDate, format: .reference(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 1))
        } else {
            Text(date.formatted(date: .omitted, time: .shortened))
        }
    }
}

enum DurationLabel {
    static func short(_ minutes: Int) -> String {
        if minutes <= 0 { return "∞" }
        return minutes < 60 ? String(localized: "\(minutes)m") : String(localized: "\(minutes / 60)h")
    }

    static func long(minutes: Int) -> String {
        if minutes <= 0 { return String(localized: "Until turned off") }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func spoken(minutes: Int) -> String {
        if minutes <= 0 { return String(localized: "Until turned off") }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
