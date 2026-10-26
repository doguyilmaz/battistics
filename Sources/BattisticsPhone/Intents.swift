import AppIntents
import BattisticsRemote

/// A Mac for Shortcuts and Siri, when more than one shares this account.
struct MacEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mac"
    static var defaultQuery: MacQuery { MacQuery() }

    let id: String
    let name: String

    /// As last read; Check Mac returns them fresh, for automations.
    @Property(title: "Battery Level") var batteryLevel: Int?
    @Property(title: "Charging") var isCharging: Bool
    @Property(title: "Keep Awake On") var keepAwakeOn: Bool
    @Property(title: "Answering") var isAnswering: Bool

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    @MainActor
    init(_ mac: MacStore.Mac) {
        id = mac.id
        name = mac.name
        let reading = MacStore.shared.reading(for: mac)
        let answering = reading?.reachable == true && reading?.status?.isFresh() == true
        isAnswering = answering
        batteryLevel = reading?.status?.battery?.percent
        isCharging = reading?.status?.battery?.isCharging ?? false
        keepAwakeOn = answering && reading?.status?.session != nil
    }
}

struct MacQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MacEntity] {
        MacStore.shared.remoteMacs.filter { identifiers.contains($0.id) }.map(MacEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [MacEntity] {
        MacStore.shared.remoteMacs.map(MacEntity.init)
    }
}

/// A Live Activity intent, so a session started from Siri or Shortcuts in
/// the background still gets its Lock Screen countdown.
struct StartKeepAwakeIntent: LiveActivityIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Starts Keep Awake on your computer.")

    @Parameter(title: "Mode", default: .displayMaySleep) var mode: KeepAwakeMode
    @Parameter(title: "Duration", default: .hour) var duration: KeepAwakeDuration

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        MacStore.shared.follow(mac)
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
    static let description = IntentDescription("Stops Keep Awake on your computer.")

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
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
    static let description = IntentDescription("Adds time to the Keep Awake session running on your computer.")

    @Parameter(title: "Time", default: .thirty) var time: IntentExtension

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        MacStore.shared.follow(mac)
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
    static let description = IntentDescription("Chooses when your computer uses Low Power Mode.")

    /// No default, so Siri and the shortcut tile ask instead of overwriting the Mac's choice.
    @Parameter(title: "Low Power Mode") var setting: IntentLowPower

    static var parameterSummary: some ParameterSummary {
        Summary("Set Mac Low Power Mode to \(\.$setting)") {
            \.$target
        }
    }

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.setLowPower(mac, policy: setting.policy) { return .result(dialog: "\(failure)") }
        return .result(dialog: "Low Power Mode on \(mac.name): \(setting.policy.label).")
    }
}

struct TurnOffMacDisplayIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Turn Off Mac Display"
    static let description = IntentDescription("Puts your computer’s display to sleep. The computer keeps running.")

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.sleepDisplay(mac) { return .result(dialog: "\(failure)") }
        return .result(dialog: "The display of \(mac.name) is off.")
    }
}

struct SleepMacIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Put Mac to Sleep"
    static let description = IntentDescription("Ends Keep Awake and puts your computer to sleep. It answers again once woken.")

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        if let failure = await MacStore.shared.sleep(mac) { return .result(dialog: "\(failure)") }
        return .result(dialog: "\(mac.name) is going to sleep.")
    }
}

struct MacStatusIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    static let title: LocalizedStringResource = "Check Mac"
    static let description = IntentDescription("Tells you your computer’s battery and whether it is kept awake.")

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MacEntity> & ProvidesDialog {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        await MacStore.shared.refreshAll()
        let entity = MacEntity(mac)
        guard entity.isAnswering, let status = MacStore.shared.reading(for: mac)?.status else {
            return .result(value: entity, dialog: "\(mac.name) is not answering.")
        }
        var sentences: [String] = []
        if let battery = status.battery {
            sentences.append(String(localized: "Battery \(battery.percent.percentText)."))
            if let time = battery.timeText { sentences.append(time + ".") }
        }
        if let deadline = status.session?.deadline, deadline > .now {
            let minutes = Int((deadline.timeIntervalSinceNow / 60).rounded(.up))
            sentences.append(String(localized: "Keep Awake is on for another \(DurationLabel.long(minutes: minutes))."))
        } else {
            sentences.append(status.session == nil ? String(localized: "Keep Awake is off.") : String(localized: "Keep Awake is on."))
        }
        return .result(value: entity, dialog: "\(sentences.joined(separator: " "))")
    }
}

/// Opens the app on a Mac, from Shortcuts, Siri or Spotlight.
struct OpenMacIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Mac"
    static let description = IntentDescription("Opens a computer in Battistics Remote.")

    @Parameter(title: "Mac") var target: MacEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard MacStore.shared.select(target.id) else { throw IntentFailure.notPaired }
        return .result()
    }
}

/// A number for Shortcuts automations, such as a reminder when the Mac runs low.
struct MacBatteryLevelIntent: AppIntent {
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed
    static let title: LocalizedStringResource = "Get Mac Battery Level"
    static let description = IntentDescription("Returns your computer’s battery level, from 0 to 100.")

    @Parameter(title: "Mac") var target: MacEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let mac = MacStore.shared.remoteMac(id: target?.id) else { throw IntentFailure.notPaired }
        await MacStore.shared.refreshAll()
        guard let reading = MacStore.shared.reading(for: mac), reading.reachable,
              reading.status?.isFresh() == true, let percent = reading.status?.battery?.percent else {
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
        AppShortcut(intent: StartKeepAwakeIntent(), phrases: ["Keep my computer awake with \(.applicationName)"],
                    shortTitle: "Keep Awake", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: StopKeepAwakeIntent(), phrases: ["Let my computer sleep with \(.applicationName)"],
                    shortTitle: "Let Sleep", systemImageName: "moon.zzz")
        AppShortcut(intent: AddKeepAwakeTimeIntent(), phrases: ["Keep my computer awake longer with \(.applicationName)"],
                    shortTitle: "Add Time", systemImageName: "plus.circle")
        AppShortcut(intent: MacStatusIntent(), phrases: ["Check my computer with \(.applicationName)"],
                    shortTitle: "Check Mac", systemImageName: "laptopcomputer")
        AppShortcut(intent: SetMacLowPowerIntent(), phrases: ["Set my computer’s Low Power Mode with \(.applicationName)"],
                    shortTitle: "Mac Low Power", systemImageName: "leaf")
        AppShortcut(intent: TurnOffMacDisplayIntent(), phrases: ["Turn off my computer’s display with \(.applicationName)"],
                    shortTitle: "Display Off", systemImageName: "display")
        AppShortcut(intent: SleepMacIntent(), phrases: ["Put my computer to sleep with \(.applicationName)"],
                    shortTitle: "Sleep Mac", systemImageName: "powersleep")
        AppShortcut(intent: OpenMacIntent(), phrases: ["Open \(\.$target) in \(.applicationName)",
                                                       "Open my computer in \(.applicationName)"],
                    shortTitle: "Open Mac", systemImageName: "arrow.up.forward.app")
    }
}
