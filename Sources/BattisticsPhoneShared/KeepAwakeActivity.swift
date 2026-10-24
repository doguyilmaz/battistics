import ActivityKit
import AppIntents
import BattisticsRemote
import Foundation

struct KeepAwakeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: RemoteStatus.Mode
        var startedAt: Date
        var deadline: Date?
        var sessionName: String?
        var batteryPercent: Int?
        var isCharging: Bool = false
        var onAdapter: Bool = false
        var lowPowerMode: Bool = false
        var watts: Double?
        var lidClosed: Bool?
        var network: RemoteStatus.Network = .wifi
        var networkName: String?
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
