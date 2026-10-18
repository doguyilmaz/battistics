import Foundation

enum TourStep: Int, CaseIterable {
    case overview, power, notifications, history, help

    var pane: DashboardPane {
        switch self {
        case .overview: .overview
        case .power: .system
        case .notifications: .notifications
        case .history: .history
        case .help: .help
        }
    }

    var title: String {
        switch self {
        case .overview: String(localized: "Your battery at a glance")
        case .power: String(localized: "Stay awake, with limits")
        case .notifications: String(localized: "Know before power runs low")
        case .history: String(localized: "Understand changes over time")
        case .help: String(localized: "Help is always close by")
        }
    }

    var detail: String {
        switch self {
        case .overview:
            String(localized: "Open Battistics from the menu bar to see charge, health, and power use. Overview brings those readings together; click a battery detail to learn more.")
        case .power:
            String(localized: "Choose a Keep Awake mode and duration here. Closed-lid mode needs the power helper. Scroll to Session Protection to choose a battery stop level; automatic stopping starts off.")
        case .notifications:
            String(localized: "Choose low-charge and temperature alerts. macOS may ask for notification permission when an alert first arrives. Keep Awake also shows an in-app warning.")
        case .history:
            String(localized: "History reveals charge, power, and temperature trends as readings accumulate. Manage recording and CSV export in Data. Your history stays on this Mac.")
        case .help:
            String(localized: "Search the built-in answers, or ask the on-device assistant when Apple Intelligence is available. Replay this tour anytime from Help. The tour never changes your power settings.")
        }
    }
}
