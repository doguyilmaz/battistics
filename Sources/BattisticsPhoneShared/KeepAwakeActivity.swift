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

        var countdownRange: ClosedRange<Date>? {
            deadline.map { RemoteStatus.countdownRange(startedAt: startedAt, deadline: $0) }
        }
    }

    var macName: String
    /// Missing on activities started by older builds, which are then ended as another Mac's.
    var macID: String?
}

/// Bridges widget and Live Activity button intents to `MacStore` in the host app.
@MainActor
enum RemoteIntentBridge {
    static var startOneHour: (() async -> Void)?
    /// Given the Live Activity's own Mac; nil means the selected one.
    static var stop: ((String?) async -> Void)?
    static var extend: ((String?, Int) async -> Void)?
}

struct StartKeepAwakeLiveIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
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

    @Parameter(title: "Mac")
    var macID: String?

    init() {}

    init(macID: String?) {
        self.macID = macID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemoteIntentBridge.stop?(macID)
        return .result()
    }
}

struct ExtendKeepAwakeLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Time to Keep Awake"
    static let description = IntentDescription("Adds time to the Keep Awake session on your Mac.")
    static let isDiscoverable = false

    @Parameter(title: "Mac")
    var macID: String?

    @Parameter(title: "Minutes")
    var minutes: Int

    init() {}

    init(macID: String?, minutes: Int) {
        self.macID = macID
        self.minutes = minutes
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemoteIntentBridge.extend?(macID, minutes)
        return .result()
    }
}

/// Backs the Control Center and Action Button toggle; runs in the app, which holds the iCloud connection.
@available(iOS 18.0, *)
struct SetKeepAwakeIntent: SetValueIntent, LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps your Mac awake for an hour, or lets it sleep again.")

    @Parameter(title: "Keep Awake")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        if value { await RemoteIntentBridge.startOneHour?() } else { await RemoteIntentBridge.stop?(nil) }
        return .result()
    }
}
