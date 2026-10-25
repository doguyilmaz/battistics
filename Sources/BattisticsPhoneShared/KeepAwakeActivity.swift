import ActivityKit
import AppIntents
import BattisticsRemote
import Foundation

struct KeepAwakeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: RemoteStatus.Mode
        var startedAt: Date
        var deadline: Date?
        var batteryPercent: Int?
        var isCharging: Bool = false
        var onAdapter: Bool = false
        var lowPowerMode: Bool = false
        var watts: Double?
        var lidClosed: Bool?
        var network: RemoteStatus.Network = .wifi
        var networkName: String?
        /// When the Mac wrote this reading, shown so the user can judge freshness.
        var lastUpdate: Date?
        /// Set by the app once the Mac has missed its heartbeat window.
        var offline: Bool?
    }

    var macName: String
}

/// Bridges widget and Live Activity button intents to `MacStore` in the host app.
@MainActor
enum RemoteIntentBridge {
    static var startOneHour: (() async -> Void)?
    static var stop: (() async -> Void)?
}

struct StartKeepAwakeLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake for 1 Hour"
    static let description = IntentDescription("Starts a 1-hour Keep Awake session on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemoteIntentBridge.startOneHour?()
        return .result()
    }
}

struct StopKeepAwakeLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Keep Awake"
    static let description = IntentDescription("Stops the active Keep Awake session on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemoteIntentBridge.stop?()
        return .result()
    }
}

/// Backs the Control Center and Action Button toggle; runs in the app, which holds the iCloud connection.
@available(iOS 18.0, *)
struct SetKeepAwakeIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps your Mac awake for an hour, or lets it sleep again.")

    @Parameter(title: "Keep Awake")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        if value { await RemoteIntentBridge.startOneHour?() } else { await RemoteIntentBridge.stop?() }
        return .result()
    }
}
