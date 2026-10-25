import BattisticsRemote
import Foundation

/// The selected Mac's latest reading, written by the app for its widgets.
struct SharedSnapshot: Codable, Equatable {
    var macName: String
    var status: RemoteStatus?
    var reachable: Bool

    var bagReady: Bool { reachable && status?.isBagReady == true }

    /// The snapshot as a widget should show it at `date`: offline once the app
    /// would have heard from the Mac by then, even with pushes throttled.
    func asOf(_ date: Date) -> SharedSnapshot {
        var copy = self
        if let status, date >= status.unheardDate { copy.reachable = false }
        return copy
    }

    static let group = "group.com.doguyilmaz.Battistics.Remote"
    private static let key = "snapshot"

    static func load() -> SharedSnapshot? {
        UserDefaults(suiteName: group)?.data(forKey: key).flatMap { try? RemoteWire.decode(Self.self, from: $0) }
    }

    func save() {
        UserDefaults(suiteName: Self.group)?.set(try? RemoteWire.encode(self), forKey: Self.key)
    }

    static func clear() {
        UserDefaults(suiteName: group)?.removeObject(forKey: key)
    }
}

struct WidgetPreferences: Codable, Equatable, Sendable {
    enum MetricFocus: String, Codable, CaseIterable, Identifiable, Sendable {
        case powerAndHealth
        case capacityAndCycles
        case networkAndSession

        var id: String { rawValue }

        var label: String {
            switch self {
            case .powerAndHealth: String(localized: "Power & Health")
            case .capacityAndCycles: String(localized: "mAh & Cycles")
            case .networkAndSession: String(localized: "Network & Session")
            }
        }
    }

    enum LockScreenLayout: String, Codable, CaseIterable, Identifiable, Sendable {
        case detailedGrid
        case cleanStatus

        var id: String { rawValue }

        var label: String {
            switch self {
            case .detailedGrid: String(localized: "Full Grid")
            case .cleanStatus: String(localized: "Clean Bar")
            }
        }
    }

    var metricFocus: MetricFocus = .powerAndHealth
    var lockScreenLayout: LockScreenLayout = .detailedGrid
    var showNetworkSSID: Bool = true

    private static let prefsKey = "widgetPreferences"

    static func load() -> WidgetPreferences {
        guard let data = UserDefaults(suiteName: SharedSnapshot.group)?.data(forKey: prefsKey),
              let decoded = try? RemoteWire.decode(Self.self, from: data) else {
            return WidgetPreferences()
        }
        return decoded
    }

    func save() {
        UserDefaults(suiteName: SharedSnapshot.group)?.set(try? RemoteWire.encode(self), forKey: Self.prefsKey)
    }
}
