import AppKit
import BattisticsCore
import BattisticsRemote
import CloudKit
import Foundation
import Observation
import SystemConfiguration

/// Shares this Mac with the user's iPhones through their private iCloud
/// database: a status record out, Start and Stop commands in. Off by default.
@MainActor
@Observable
final class RemoteAccessModel {
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Prefs.remoteEnabled)
            if enabled {
                NSApplication.shared.registerForRemoteNotifications()
                Task { await sync() }
            } else {
                Task { await withdraw() }
            }
        }
    }
    var closedLidAllowed: Bool {
        didSet {
            UserDefaults.standard.set(closedLidAllowed, forKey: Prefs.remoteClosedLidAllowed)
            if closedLidAllowed, cloud != nil {
                Task { try? await helper.prepareForLidSleep() }
            }
            publishSoon()
        }
    }
    /// Why sharing is not working right now, in the user's language.
    private(set) var problem: String?
    private(set) var lastPublished: Date?

    @ObservationIgnored private let awake: KeepAwakeModel
    @ObservationIgnored private let automation: AutomationModel
    @ObservationIgnored private let helper: PowerHelperClient
    @ObservationIgnored let network: NetworkMonitor
    /// Updated after a phone changes a setting, so the Mac's own panes show it too.
    @ObservationIgnored private let powerSettings: PowerSettingsModel?
    @ObservationIgnored private let cloud: RemoteCloud?
    @ObservationIgnored private let chargeHistory: @Sendable () async -> [RemoteStatus.ChargePoint]
    /// The app's latest reading, so polls do not each read the battery again.
    @ObservationIgnored private let battery: @MainActor () -> BatterySnapshot?
    /// The last published status before history and power settings were added, for cheap comparisons.
    @ObservationIgnored private var lastCheap: RemoteStatus?
    @ObservationIgnored private var lastCommand: RemoteStatus.CommandResult?
    @ObservationIgnored private var lastCommandAt: Date?
    @ObservationIgnored private var extras: RemoteStatus.Extras?
    /// Ran but not yet deleted, so a failed delete neither runs a command
    /// twice nor leaves its record behind: the delete is retried next sync.
    @ObservationIgnored private var handledCommands: Set<String> = []
    @ObservationIgnored private var retryAt: Date?
    @ObservationIgnored private var cachedPower: (settings: PowerSettings?, at: Date)?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var pendingPublish: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var pushObserver: NSObjectProtocol?
    @ObservationIgnored private var powerStateObserver: NSObjectProtocol?
    @ObservationIgnored let macID: String

    init(awake: KeepAwakeModel, automation: AutomationModel, helper: PowerHelperClient,
         network: NetworkMonitor, powerSettings: PowerSettingsModel? = nil,
         cloud: RemoteCloud? = RemoteCloud.isEntitled ? RemoteCloud() : nil,
         battery: @escaping @MainActor () -> BatterySnapshot? = { BatteryReader.read() },
         chargeHistory: @escaping @Sendable () async -> [RemoteStatus.ChargePoint] = { [] }) {
        self.awake = awake
        self.automation = automation
        self.helper = helper
        self.network = network
        self.powerSettings = powerSettings
        self.cloud = cloud
        self.chargeHistory = chargeHistory
        self.battery = battery
        if let saved = UserDefaults.standard.string(forKey: Prefs.remoteMacID) {
            macID = saved
        } else {
            macID = UUID().uuidString
            UserDefaults.standard.set(macID, forKey: Prefs.remoteMacID)
        }
        enabled = UserDefaults.standard.bool(forKey: Prefs.remoteEnabled)
        closedLidAllowed = UserDefaults.standard.bool(forKey: Prefs.remoteClosedLidAllowed)
        network.onChange = { [weak self] in self?.publishSoon() }
        pushObserver = NotificationCenter.default.addObserver(
            forName: .battisticsRemotePush, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.sync() } }
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cachedPower = nil
                self?.publishSoon()
            }
        }
        observeSession()
        observePowerSettings()
        startTicker()
        if enabled, cloud != nil {
            NSApplication.shared.registerForRemoteNotifications()
            Task { await sync() }
        }
    }

    /// False for builds not signed for iCloud, such as local ad-hoc builds.
    var isAvailable: Bool { cloud != nil }

    // MARK: iCloud

    /// Runs commands addressed to this Mac, then publishes the result. The
    /// heartbeat goes out even when reading commands fails, so a fetch error
    /// never makes a running Mac look offline on the phone.
    func sync() async {
        guard enabled, let cloud, !syncing else { return }
        if let retryAt, retryAt > .now { return }
        syncing = true
        defer { syncing = false }
        var failure: Error?
        var handled = false
        var recordMissing = false
        do {
            let snapshot = try await cloud.fetchChanges()
            recordMissing = (snapshot.isFull && snapshot.statuses[macID] == nil)
                || snapshot.removedStatuses.contains(macID)
            // Left behind by a phone whose delete failed for a Mac that is gone; seen at launch.
            for command in snapshot.commands where command.macID != macID
                && -command.request.sentAt.timeIntervalSinceNow > 10 * 60 {
                handledCommands.insert(command.recordName)
            }
            let mine = snapshot.commands
                .filter { $0.macID == macID && !handledCommands.contains($0.recordName) }
                .sorted { $0.request.sentAt < $1.request.sentAt }
            for command in mine {
                handledCommands.insert(command.recordName)
                guard -command.request.sentAt.timeIntervalSinceNow < RemoteRequest.lifetime else { continue }
                lastCommand = .init(id: command.request.id, failure: await handle(command.request))
                lastCommandAt = .now
                // Each answer goes out before the next command replaces it, or that phone waits in vain.
                if mine.count > 1 { try? await publish(force: true) }
                handled = true
            }
            try await cloud.delete(Array(handledCommands))
            handledCommands.removeAll()
        } catch {
            failure = error
        }
        // A lost or recreated zone has no status record, however unchanged this Mac is.
        let zoneGone = [.zoneNotFound, .userDeletedZone].contains((failure as? CKError)?.code)
        if (failure as? CKError)?.retryAfterSeconds == nil {
            do {
                try await publish(force: handled || zoneGone || recordMissing)
            } catch {
                failure = error
            }
        }
        if let seconds = (failure as? CKError)?.retryAfterSeconds {
            retryAt = .now.addingTimeInterval(seconds)
        }
        problem = failure.map(Self.describe)
    }

    /// Compares the cheap part of the status first, so a poll that changes
    /// nothing costs no history query and no `pmset` spawn.
    private func publish(force: Bool) async throws {
        guard enabled, let cloud else { return }
        var status = status()
        status.lastCommand = lastCommand
        if !force, let lastCheap, let lastPublished, -lastPublished.timeIntervalSinceNow < status.expectedHeartbeat {
            var compared = status
            compared.readAt = lastCheap.readAt
            compared.battery?.watts = lastCheap.battery?.watts
            compared.battery?.temperatureC = lastCheap.battery?.temperatureC
            compared.battery?.voltageMV = lastCheap.battery?.voltageMV
            compared.battery?.amperageMA = lastCheap.battery?.amperageMA
            compared.battery?.currentCapacityMah = lastCheap.battery?.currentCapacityMah
            if compared == lastCheap { return }
        }
        let cheap = status
        status = await enriched(status)
        guard enabled else { return }
        try await cloud.publish(status, macID: macID)
        // Sharing was turned off while the save was in flight: take the record back down.
        guard enabled else {
            try? await cloud.delete([macID])
            return
        }
        lastCheap = cheap
        lastPublished = Date()
    }

    /// Coalesces bursts of changes into one write.
    private func publishSoon(force: Bool = false) {
        guard enabled, cloud != nil else { return }
        pendingPublish?.cancel()
        pendingPublish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.publish(force: force)
                self.problem = nil
            } catch {
                self.problem = Self.describe(error)
            }
        }
    }

    /// Removes this Mac from the user's phones.
    private func withdraw() async {
        pendingPublish?.cancel()
        lastCheap = nil
        lastPublished = nil
        problem = nil
        // Retried by the ticker until it lands, or phones keep a ghost of this Mac.
        guard let cloud else { return }
        let removed: Bool
        do {
            try await cloud.delete([macID])
            removed = true
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
            removed = true
        } catch {
            removed = false
        }
        UserDefaults.standard.set(!removed && !enabled, forKey: Prefs.remoteWithdrawPending)
    }

    /// Low Power policy changes made in the Mac's own panes post no system notification.
    private func observePowerSettings() {
        guard let powerSettings else { return }
        withObservationTracking {
            _ = powerSettings.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.cachedPower = nil
                self?.publishSoon(force: true)
                self?.observePowerSettings()
            }
        }
    }

    private func observeSession() {
        withObservationTracking {
            _ = awake.session
            _ = awake.lastEnd
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publishSoon()
                self?.observeSession()
            }
        }
    }

    /// Polls for phone commands because macOS throttles silent pushes: every
    /// few seconds while a session runs or right after a command, otherwise
    /// slower. Each poll is a delta fetch, so an idle zone costs one small request.
    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.pollInterval ?? 15
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                if !self.enabled, UserDefaults.standard.bool(forKey: Prefs.remoteWithdrawPending) {
                    await self.withdraw()
                }
                await self.sync()
            }
        }
    }

    private var pollInterval: TimeInterval {
        let recentCommand = lastCommandAt.map { -$0.timeIntervalSinceNow < 120 } ?? false
        return awake.isActive || recentCommand ? 4 : 15
    }

    private static func describe(_ error: Error) -> String {
        switch (error as? CKError)?.code {
        case .notAuthenticated:
            String(localized: "Sign in to iCloud on this Mac to share it with your iPhone.")
        case .networkUnavailable, .networkFailure:
            String(localized: "This Mac is offline. Sharing resumes when it reconnects.")
        case .quotaExceeded:
            String(localized: "iCloud storage is full.")
        default:
            String(localized: "iCloud did not accept the update. Battistics will try again.")
        }
    }

    // MARK: Commands

    /// nil when the command was carried out.
    func handle(_ request: RemoteRequest) async -> RemoteFailure? {
        guard enabled else { return .init(.unavailable) }
        switch request.operation {
        case .stop:
            if awake.isActive || awake.isChanging { awake.stop(reason: .phone) }
            return nil
        case .start:
            return await start(request)
        case .setLowPower:
            return await setLowPower(request)
        case .sleepDisplay:
            return await sleepDisplay()
        case .inspect:
            extras = await Self.inspect()
            return nil
        case .unknown:
            return .init(.invalidRequest)
        }
    }

    /// Accessory batteries and the busiest apps, measured only when a phone asks.
    private static func inspect() async -> RemoteStatus.Extras {
        async let hid = PeripheralBatteryReader.read()
        async let bluetooth = BluetoothBatteryReader.fetch()
        async let samples = ProcessEnergySampler.sample(over: .seconds(3), limit: 5)
        var accessories: [String: PeripheralBattery] = [:]
        for battery in await hid + bluetooth { accessories[battery.id] = battery }
        return .init(
            sampledAt: .now,
            accessories: accessories.values
                .sorted(by: PeripheralBattery.displayOrder)
                .map { .init(name: $0.name == PeripheralBattery.unknownName ? String(localized: "Accessory") : $0.name,
                             percent: $0.percent, detail: $0.detail) },
            apps: await samples.map { .init(name: $0.name, cpuPercent: ($0.cpuPercent * 10).rounded() / 10,
                                            energyShare: $0.energyShare) })
    }

    private func setLowPower(_ request: RemoteRequest) async -> RemoteFailure? {
        guard let policy = request.lowPowerPolicy else {
            return .init(.invalidRequest)
        }
        let setting = policy.setting
        do {
            try await helper.requireCurrent()
            try await helper.apply(.lowPowerMode(setting))
        } catch {
            return .init(.helperUnavailable)
        }
        let verified = if let powerSettings { await powerSettings.refresh() } else { await PowerSettingsReader.fetch() }
        cachedPower = (verified, .now)
        guard PowerChange.lowPowerMode(setting).isReflected(in: verified) else {
            return .init(.startFailed, String(localized: "macOS did not apply the Low Power Mode change."))
        }
        return nil
    }

    private func sleepDisplay() async -> RemoteFailure? {
        do {
            try await DisplaySleep.now()
            return nil
        } catch {
            return .init(.startFailed, String(localized: "macOS could not put the display to sleep."))
        }
    }

    private func start(_ request: RemoteRequest) async -> RemoteFailure? {
        let minutes = request.durationMinutes ?? 0
        guard RemoteRequest.allowedDurations.contains(minutes),
              let duration = KeepAwakeDuration(rawValue: minutes),
              let mode = request.mode.flatMap({ KeepAwakeMode(rawValue: $0.rawValue) }) else {
            return .init(.invalidRequest)
        }
        guard !awake.isActive, !awake.isChanging, !awake.isAwaitingHelperApproval else {
            return .init(.busy)
        }
        if mode == .lidClosed {
            guard closedLidAllowed else {
                return .init(.closedLidNotAllowed)
            }
            do {
                try await helper.requireCurrent()
            } catch {
                return .init(.helperUnavailable)
            }
        }
        let id = UUID().uuidString
        let name = request.deviceName.map { String($0.prefix(64)) }.flatMap { $0.isEmpty ? nil : $0 }
        let task = awake.start(mode: mode, duration: duration, id: id, allowHelperSetup: false,
                               name: name ?? String(localized: "iPhone"), origin: .phone)
        await task?.value
        guard awake.sessionIdentifier == id, awake.isActive else {
            let message = awake.errorMessage ?? String(localized: "Keep Awake could not start.")
            let unattended = KeepAwakeModel.isUnattended(origin: .phone, mode: mode)
            return .init(awake.safety.blockingEvent(unattended: unattended) == nil ? .startFailed : .protection, message)
        }
        return nil
    }

    // MARK: Status

    /// `pmset` is a process spawn, so its answer is reused for a minute unless
    /// the power state changed.
    private func powerSettings() async -> PowerSettings? {
        if let cachedPower, -cachedPower.at.timeIntervalSinceNow < 60 { return cachedPower.settings }
        let settings = await PowerSettingsReader.fetch()
        cachedPower = (settings, .now)
        return settings
    }

    func fullStatus() async -> RemoteStatus {
        await enriched(status())
    }

    private func enriched(_ cheap: RemoteStatus) async -> RemoteStatus {
        var status = cheap
        async let historyTask = chargeHistory()
        let power = await powerSettings()
        let history = await historyTask
        status.chargeHistory = history.isEmpty ? nil : history
        if let power, var battery = status.battery {
            battery.lowPowerPolicy = power.lowPowerMode.map(RemoteStatus.LowPowerPolicy.init)
            if let sourceActive = battery.onAdapter ? power.ac?.lowPowerMode : power.battery?.lowPowerMode {
                battery.lowPowerMode = sourceActive
            }
            status.battery = battery
        }
        return status
    }

    func status(at now: Date = Date()) -> RemoteStatus {
        let snapshot = battery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let battery = snapshot.flatMap { snapshot -> RemoteStatus.Battery? in
            guard snapshot.batteryInstalled else { return nil }
            let roundedWatts = snapshot.watts.map { ($0 * 10).rounded() / 10 }
            let roundedTemp = snapshot.temperatureC.map { ($0 * 10).rounded() / 10 }
            return .init(
                percent: snapshot.percent,
                isCharging: snapshot.isCharging,
                onAdapter: snapshot.externalConnected,
                minutesRemaining: snapshot.timeRemainingMin,
                healthPercent: Int(snapshot.displayHealthPercent.rounded()),
                lowPowerMode: lowPower,
                watts: roundedWatts,
                adapterWatts: snapshot.adapter?.watts,
                temperatureC: roundedTemp,
                cycleCount: snapshot.cycleCount,
                designCycleCount: snapshot.designCycleCount,
                currentCapacityMah: snapshot.rawCurrentCapacity > 0 ? snapshot.rawCurrentCapacity : nil,
                maxCapacityMah: snapshot.currentMaxCapacity > 0 ? snapshot.currentMaxCapacity : nil,
                designCapacityMah: snapshot.designCapacity > 0 ? snapshot.designCapacity : nil,
                voltageMV: snapshot.voltageMV,
                amperageMA: snapshot.amperageMA,
                adapterName: snapshot.adapter?.name,
                manufactureDate: snapshot.manufactureDate
            )
        }
        let session = awake.session.map { session in
            RemoteStatus.Session(
                mode: RemoteStatus.Mode(rawValue: session.mode.rawValue) ?? .displayMaySleep,
                origin: awake.sessionOrigin, name: automation.activeTaskName ?? awake.sessionName,
                startedAt: session.startedAt, deadline: session.deadline)
        }
        let protection = awake.safety.effectiveConfiguration
        var status = RemoteStatus(
            machineName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac",
            readAt: now,
            battery: battery,
            session: session,
            lastEnd: awake.lastEnd,
            network: network.state,
            networkName: network.ssid ?? (network.state == .hotspot ? network.preferredHotspotPhoneName : nil),
            lidClosed: Clamshell.read()?.isClosed,
            thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
            protection: .init(
                stopAtPercent: protection.stopOnLowBattery ? protection.effectiveStopPercent : nil,
                warnAtPercent: protection.warnOnLowBattery ? protection.effectiveWarningPercent : nil,
                closedLidAllowed: closedLidAllowed
            ),
            macModel: Self.hardwareModel,
            osVersion: Self.osVersion,
            pairedPhoneName: network.preferredHotspotPhoneName,
            heartbeatSeconds: RemoteStatus.heartbeat(duringSession: session != nil)
        )
        status.extras = extras
        return status
    }

    private static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)\(version.patchVersion > 0 ? ".\(version.patchVersion)" : "")"
    }()

    private static let hardwareModel = macHardwareModel()

    private static func macHardwareModel() -> String? {
        let raw = IssueReporter.hardwareModel
        guard raw != "unknown" else { return nil }
        let friendly: String? = switch raw {
        case "Mac14,9", "Mac14,5": "MacBook Pro 14\""
        case "Mac14,10", "Mac14,6": "MacBook Pro 16\""
        case "Mac14,7": "MacBook Pro 13\""
        case "Mac14,2": "MacBook Air 13\""
        case "Mac14,15": "MacBook Air 15\""
        case "Mac15,3", "Mac15,6", "Mac15,8", "Mac15,10": "MacBook Pro 14\""
        case "Mac15,7", "Mac15,9", "Mac15,11": "MacBook Pro 16\""
        case "Mac15,12": "MacBook Air 13\""
        case "Mac15,13": "MacBook Air 15\""
        case "Mac16,1", "Mac16,6", "Mac16,8": "MacBook Pro 14\""
        case "Mac16,5", "Mac16,7": "MacBook Pro 16\""
        default: raw.hasPrefix("MacBook") ? raw : nil
        }
        if let friendly, friendly != raw {
            return "\(friendly) (\(raw))"
        }
        return raw
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> RemoteStatus.Thermal {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}

extension Notification.Name {
    /// Posted by the app delegate when iCloud reports a change.
    static let battisticsRemotePush = Notification.Name("battisticsRemotePush")
}

private extension RemoteStatus.LowPowerPolicy {
    init(_ setting: LowPowerModeSetting) {
        self = switch setting {
        case .never: .never
        case .onlyOnBattery: .onlyOnBattery
        case .onlyOnPowerAdapter: .onlyOnAdapter
        case .always: .always
        }
    }

    var setting: LowPowerModeSetting {
        switch self {
        case .never: .never
        case .onlyOnBattery: .onlyOnBattery
        case .onlyOnAdapter: .onlyOnPowerAdapter
        case .always: .always
        }
    }
}
