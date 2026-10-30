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
        var lastUpdate: Date

        var countdownRange: ClosedRange<Date>? {
            deadline.map { RemoteStatus.countdownRange(startedAt: startedAt, deadline: $0) }
        }
    }

    var macName: String
    var macID: String
}

/// Bridges widget and Live Activity button intents to `MacStore` in the host app.
@MainActor
enum RemoteIntentBridge {
    /// Each takes the Mac of the widget or Live Activity it came from; nil
    /// means the selected one. Minutes 0 means until turned off.
    static var start: ((String?, RemoteStatus.Mode, Int) async -> Void)?
    static var stop: ((String?) async -> Void)?
    static var extend: ((String?, Int) async -> Void)?
    static var sleepDisplay: (() async -> Void)?
}

struct StartKeepAwakeLiveIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Keep Mac Awake for 1 Hour"
    static let description = IntentDescription("Starts a 1-hour Keep Awake session on your computer.")
    static let isDiscoverable = false

    @Parameter(title: "Mac")
    var macID: String?

    init() {}

    init(macID: String?) {
        self.macID = macID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemoteIntentBridge.start?(macID, .displayMaySleep, 60)
        return .result()
    }
}

struct StopKeepAwakeLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Keep Awake"
    static let description = IntentDescription("Stops the active Keep Awake session on your computer.")
    static let isDiscoverable = false

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
    static let description = IntentDescription("Adds time to the Keep Awake session on your computer.")
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

/// Backs the Control Center and Action Button display control; runs in the app.
struct SleepMacDisplayLiveIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Turn Off Mac Display"
    static let description = IntentDescription("Puts your computer’s display to sleep. The computer keeps running.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemoteIntentBridge.sleepDisplay?()
        return .result()
    }
}

enum KeepAwakeMode: String, AppEnum {
    case displayMaySleep, displayOn, lidClosed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .displayMaySleep: "Screen Off", .displayOn: "Screen On", .lidClosed: "Lid Closed",
    ]

    var mode: RemoteStatus.Mode { RemoteStatus.Mode(rawValue: rawValue)! }
}

enum KeepAwakeDuration: Int, AppEnum {
    case fifteen = 15, thirty = 30, hour = 60, twoHours = 120, fourHours = 240, sixHours = 360, twelveHours = 720,
         untilOff = 0

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Duration"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fifteen: "15 minutes", .thirty: "30 minutes", .hour: "1 hour", .twoHours: "2 hours",
        .fourHours: "4 hours", .sixHours: "6 hours", .twelveHours: "12 hours", .untilOff: "Until turned off",
    ]
}

/// What one Control Center control starts; each placed control keeps its own.
@available(iOS 18.0, *)
struct KeepAwakeControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Choose the mode and how long this control keeps your computer awake.")

    @Parameter(title: "Mode", default: .displayMaySleep) var mode: KeepAwakeMode
    @Parameter(title: "Duration", default: .hour) var duration: KeepAwakeDuration
}

/// Backs the Control Center and Action Button toggle; runs in the app, which holds the iCloud connection.
@available(iOS 18.0, *)
struct SetKeepAwakeIntent: SetValueIntent, LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps your computer awake, or lets it sleep again.")
    static let isDiscoverable = false

    @Parameter(title: "Keep Awake")
    var value: Bool

    @Parameter(title: "Mode", default: .displayMaySleep) var mode: KeepAwakeMode
    @Parameter(title: "Duration", default: .hour) var duration: KeepAwakeDuration

    init() {}

    init(mode: KeepAwakeMode, duration: KeepAwakeDuration) {
        self.mode = mode
        self.duration = duration
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if value {
            await RemoteIntentBridge.start?(nil, mode.mode, duration.rawValue)
        } else {
            await RemoteIntentBridge.stop?(nil)
        }
        return .result()
    }
}
