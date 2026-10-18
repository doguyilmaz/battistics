import BattisticsCore
import Foundation

enum KeepAwakeProfile: String, CaseIterable, Identifiable {
    case aiFocus, longBuild, overnight, presentation

    var id: Self { self }
    var mode: KeepAwakeMode { self == .presentation ? .displayOn : .displayMaySleep }
    var duration: KeepAwakeDuration {
        switch self {
        case .aiFocus: .twoHours
        case .longBuild: .fourHours
        case .overnight: .twelveHours
        case .presentation: .oneHour
        }
    }
    var title: String {
        switch self {
        case .aiFocus: String(localized: "AI Focus")
        case .longBuild: String(localized: "Long Build")
        case .overnight: String(localized: "Overnight")
        case .presentation: String(localized: "Presentation")
        }
    }
    var symbol: String {
        switch self {
        case .aiFocus: "sparkles"
        case .longBuild: "hammer"
        case .overnight: "moon"
        case .presentation: "display"
        }
    }
    var detail: String {
        switch self {
        case .aiFocus: String(localized: "2 hours · display may sleep. A timer for AI work; use MCP to stop when the task finishes.")
        case .longBuild: String(localized: "4 hours · display may sleep. For long builds, tests and exports.")
        case .overnight: String(localized: "12 hours · display may sleep. Connect power and leave the lid open.")
        case .presentation: String(localized: "1 hour · display stays on. For demos and presentations.")
        }
    }
}
