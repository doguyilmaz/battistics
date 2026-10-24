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
    /// Returns the SSID / network name when available, falling back to the
    /// phone's own name when the Mac is on a Personal Hotspot.
    func resolvedNetworkName(fallbackHotspot: String? = nil) -> String? {
        if let name = networkName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if network == .hotspot, let fallback = fallbackHotspot?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    func networkDisplayLabel(fallbackHotspot: String? = nil) -> String {
        if let name = resolvedNetworkName(fallbackHotspot: fallbackHotspot) {
            return "\(network.label) · \(name)"
        }
        return network.label
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

    var shortBadge: String {
        switch self {
        case .never: String(localized: "LPM Off")
        case .onlyOnBattery: String(localized: "LPM Battery")
        case .onlyOnAdapter: String(localized: "LPM Adapter")
        case .always: String(localized: "LPM On")
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

enum DurationLabel {
    static func short(_ minutes: Int) -> String {
        if minutes <= 0 { return "∞" }
        return minutes < 60 ? String(localized: "\(minutes)m") : String(localized: "\(minutes / 60)h")
    }

    static func long(minutes: Int) -> String {
        if minutes <= 0 { return String(localized: "Until stopped") }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func spoken(minutes: Int) -> String {
        if minutes <= 0 { return String(localized: "Until turned off") }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
