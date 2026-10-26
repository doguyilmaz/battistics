import AppIntents
import BattisticsRemote

/// A Live Activity intent, so a session started from Siri or Shortcuts in
/// the background still gets its Lock Screen countdown.
struct StartKeepAwakeIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Starts Keep Awake on your Mac.")

    @Parameter(title: "Mode", default: .displayMaySleep) var mode: KeepAwakeMode
    @Parameter(title: "Duration", default: .hour) var duration: KeepAwakeDuration

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.start(mac, mode: mode.mode, minutes: duration.rawValue) {
            return .result(dialog: "\(failure)")
        }
        if duration == .untilOff { return .result(dialog: "\(mac.name) stays awake until you turn it off.") }
        return .result(dialog: "\(mac.name) stays awake for \(DurationLabel.long(minutes: duration.rawValue)).")
    }
}

struct StopKeepAwakeIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed
    static let title: LocalizedStringResource = "Let Mac Sleep"
    static let description = IntentDescription("Stops Keep Awake on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.stop(mac) { return .result(dialog: "\(failure)") }
        return .result(dialog: "Keep Awake is off on \(mac.name).")
    }
}

enum IntentExtension: Int, AppEnum {
    case fifteen = 15, thirty = 30, hour = 60, twoHours = 120

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fifteen: "15 minutes", .thirty: "30 minutes", .hour: "1 hour", .twoHours: "2 hours",
    ]
}

struct AddKeepAwakeTimeIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed
    static let title: LocalizedStringResource = "Add Time to Keep Awake"
    static let description = IntentDescription("Adds time to the Keep Awake session running on your Mac.")

    @Parameter(title: "Time", default: .thirty) var time: IntentExtension

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.extend(mac, minutes: time.rawValue) { return .result(dialog: "\(failure)") }
        return .result(dialog: "\(mac.name) stays awake \(DurationLabel.long(minutes: time.rawValue)) longer.")
    }
}

enum IntentLowPower: String, AppEnum {
    case never, onlyOnBattery, onlyOnAdapter, always

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Low Power Mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .never: "Never", .onlyOnBattery: "Only on Battery", .onlyOnAdapter: "Only on Power Adapter", .always: "Always",
    ]

    var policy: RemoteStatus.LowPowerPolicy { RemoteStatus.LowPowerPolicy(rawValue: rawValue)! }
}

struct SetMacLowPowerIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Set Mac Low Power Mode"
    static let description = IntentDescription("Chooses when your Mac uses Low Power Mode.")

    /// No default, so Siri and the shortcut tile ask instead of overwriting the Mac's choice.
    @Parameter(title: "Low Power Mode") var setting: IntentLowPower

    static var parameterSummary: some ParameterSummary {
        Summary("Set Mac Low Power Mode to \(\.$setting)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.setLowPower(mac, policy: setting.policy) { return .result(dialog: "\(failure)") }
        return .result(dialog: "Low Power Mode on \(mac.name): \(setting.policy.label).")
    }
}

struct TurnOffMacDisplayIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Turn Off Mac Display"
    static let description = IntentDescription("Puts your Mac’s display to sleep. The Mac keeps running.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.sleepDisplay(mac) { return .result(dialog: "\(failure)") }
        return .result(dialog: "The display of \(mac.name) is off.")
    }
}

struct MacStatusIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Check Mac"
    static let description = IntentDescription("Tells you your Mac’s battery and whether it is kept awake.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        await MacStore.shared.refreshAll()
        guard let reading = MacStore.shared.reading(for: mac), reading.reachable, let status = reading.status else {
            return .result(dialog: "\(mac.name) is not answering.")
        }
        let battery = status.battery.map { String(localized: "Battery \($0.percent)%.") } ?? ""
        let awake = status.session == nil ? String(localized: "Keep Awake is off.") : String(localized: "Keep Awake is on.")
        return .result(dialog: "\(battery) \(awake)")
    }
}

/// A number for Shortcuts automations, such as a reminder when the Mac runs low.
struct MacBatteryLevelIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed
    static let title: LocalizedStringResource = "Get Mac Battery Level"
    static let description = IntentDescription("Returns your Mac’s battery level, from 0 to 100.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let mac = MacStore.shared.selected else { throw IntentFailure.notPaired }
        await MacStore.shared.refreshAll()
        guard let reading = MacStore.shared.reading(for: mac), reading.reachable,
              let percent = reading.status?.battery?.percent else {
            throw IntentFailure.noReading(mac.name)
        }
        return .result(value: percent)
    }
}

enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case notPaired
    case noReading(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notPaired: "Open Battistics Remote to connect to your Mac first."
        case .noReading(let name): "\(name) is not answering or has no battery."
        }
    }
}

struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartKeepAwakeIntent(), phrases: ["Keep my Mac awake with \(.applicationName)"],
                    shortTitle: "Keep Awake", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: StopKeepAwakeIntent(), phrases: ["Let my Mac sleep with \(.applicationName)"],
                    shortTitle: "Let Sleep", systemImageName: "moon.zzz")
        AppShortcut(intent: AddKeepAwakeTimeIntent(), phrases: ["Keep my Mac awake longer with \(.applicationName)"],
                    shortTitle: "Add Time", systemImageName: "plus.circle")
        AppShortcut(intent: MacStatusIntent(), phrases: ["Check my Mac with \(.applicationName)"],
                    shortTitle: "Check Mac", systemImageName: "laptopcomputer")
        AppShortcut(intent: SetMacLowPowerIntent(), phrases: ["Set my Mac’s Low Power Mode with \(.applicationName)"],
                    shortTitle: "Mac Low Power", systemImageName: "leaf")
        AppShortcut(intent: TurnOffMacDisplayIntent(), phrases: ["Turn off my Mac’s display with \(.applicationName)"],
                    shortTitle: "Display Off", systemImageName: "display")
    }
}
