import Foundation

enum TourStep: Int, CaseIterable {
    case overview, power, profiles, protection, automation, notifications, history, help

    var pane: DashboardPane {
        switch self {
        case .overview: .overview
        case .power, .profiles, .protection, .automation: .system
        case .notifications: .notifications
        case .history: .history
        case .help: .help
        }
    }

    var title: String {
        switch self {
        case .overview: String(localized: "Your battery at a glance")
        case .power: String(localized: "Stay awake, with limits")
        case .profiles: String(localized: "Start with a ready-made profile")
        case .protection: String(localized: "Choose when Keep Awake should stop")
        case .automation: String(localized: "Keep Awake for developer tasks")
        case .notifications: String(localized: "Know before power runs low")
        case .history: String(localized: "Understand changes over time")
        case .help: String(localized: "Help is always close by")
        }
    }

    var detail: String {
        switch self {
        case .overview:
            String(localized: "These gauges show your current charge and battery health. Open Battistics from the menu bar whenever you need a quick check.")
        case .power:
            String(localized: "This switch starts Keep Awake. Choose whether the display stays on and set a time limit below it. Closed-lid mode requires the power helper. Nothing starts during this tour.")
        case .profiles:
            String(localized: "AI Focus, Long Build, Overnight and Presentation combine a mode with a time limit. They keep your protection settings. AI Focus is a timer; it does not detect when an AI task finishes.")
        case .protection:
            String(localized: "Turn this on to end Keep Awake at a battery level you choose. It allows normal sleep; it does not shut down the Mac. Low-battery warnings below are on by default.")
        case .automation:
            String(localized: "Enable local automation to use battistics run for builds and scripts. For interactive AI work, use MCP to start and stop each task. Terminal setup and MCP configuration appear below once this is on.")
        case .notifications:
            String(localized: "Choose low-charge and temperature alerts. macOS may ask for notification permission when an alert first arrives. Keep Awake also shows an in-app warning.")
        case .history:
            String(localized: "History reveals charge, power, and temperature trends as readings accumulate. Manage recording and CSV export in Data. Your history stays on this Mac.")
        case .help:
            String(localized: "Search here for built-in answers. On supported Macs, the on-device assistant can help find an answer. Replay this tour from Help anytime. Your settings have not changed.")
        }
    }
}
