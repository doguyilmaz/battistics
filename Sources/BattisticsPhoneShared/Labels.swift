import BattisticsRemote
import SwiftUI

extension RemoteStatus.Mode {
    var label: String {
        switch self {
        case .displayMaySleep: String(localized: "Display may sleep")
        case .displayOn: String(localized: "Display on")
        case .lidClosed: String(localized: "Lid closed")
        }
    }

    var symbol: String {
        switch self {
        case .displayMaySleep: "moon"
        case .displayOn: "sun.max"
        case .lidClosed: "laptopcomputer"
        }
    }
}

extension RemoteStatus.Origin {
    var label: String {
        switch self {
        case .manual: String(localized: "Started on the Mac")
        case .profile: String(localized: "Profile")
        case .terminal: String(localized: "Terminal command")
        case .ai: String(localized: "AI task")
        case .phone: String(localized: "Started from iPhone")
        }
    }
}

extension RemoteStatus.EndReason {
    var label: String {
        switch self {
        case .timer: String(localized: "Time ran out")
        case .user: String(localized: "Stopped on the Mac")
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

enum DurationLabel {
    static func short(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "\(minutes)m") : String(localized: "\(minutes / 60)h")
    }

    static func long(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func spoken(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
