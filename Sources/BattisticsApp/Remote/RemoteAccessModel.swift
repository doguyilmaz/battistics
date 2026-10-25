import AppKit
import BattisticsCore
import BattisticsRemote
import CloudKit
import Foundation
import Observation

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
    @ObservationIgnored private let cloud: RemoteCloud?
    @ObservationIgnored private let chargeHistory: @Sendable () async -> [RemoteStatus.ChargePoint]
    @ObservationIgnored private var lastSent: RemoteStatus?
    @ObservationIgnored private var lastCommand: RemoteStatus.CommandResult?
    @ObservationIgnored private var lastCommandAt: Date?
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
         network: NetworkMonitor, cloud: RemoteCloud? = RemoteCloud.isEntitled ? RemoteCloud() : nil,
         chargeHistory: @escaping @Sendable () async -> [RemoteStatus.ChargePoint] = { [] }) {
        self.awake = awake
        self.automation = automation
        self.helper = helper
        self.network = network
        self.cloud = cloud
        self.chargeHistory = chargeHistory
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
        startTicker()
        if enabled, cloud != nil {
            NSApplication.shared.registerForRemoteNotifications()
            if closedLidAllowed {
                Task { try? await helper.prepareForLidSleep() }
            }
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
        do {
            let snapshot = try await cloud.fetchChanges()
            let mine = snapshot.commands
                .filter { $0.macID == macID && !handledCommands.contains($0.recordName) }
                .sorted { $0.request.sentAt < $1.request.sentAt }
            for command in mine {
                handledCommands.insert(command.recordName)
                guard -command.request.sentAt.timeIntervalSinceNow < RemoteRequest.lifetime else { continue }
                lastCommand = .init(id: command.request.id, failure: await handle(command.request))
                lastCommandAt = .now
                handled = true
            }
            try await cloud.delete(Array(handledCommands))
            handledCommands.removeAll()
        } catch {
            failure = error
        }
        do {
            try await publish(force: handled)
        } catch {
            failure = error
        }
        if let seconds = (failure as? CKError)?.retryAfterSeconds {
            retryAt = .now.addingTimeInterval(seconds)
        }
        problem = failure.map(Self.describe)
    }

    private func publish(force: Bool) async throws {
        guard enabled, let cloud else { return }
        var status = await fullStatus()
        status.lastCommand = lastCommand
        if !force, let lastSent, let lastPublished, -lastPublished.timeIntervalSinceNow < status.expectedHeartbeat {
            var compared = status
            compared.readAt = lastSent.readAt
            compared.chargeHistory = lastSent.chargeHistory
            compared.battery?.watts = lastSent.battery?.watts
            compared.battery?.temperatureC = lastSent.battery?.temperatureC
            compared.battery?.voltageMV = lastSent.battery?.voltageMV
            compared.battery?.amperageMA = lastSent.battery?.amperageMA
            compared.battery?.currentCapacityMah = lastSent.battery?.currentCapacityMah
            if compared == lastSent { return }
        }
        // Sharing may have been turned off while the status was being read.
        guard enabled else { return }
        try await cloud.publish(status, macID: macID)
        lastSent = status
        lastPublished = Date()
    }

    /// Coalesces bursts of changes into one write.
    private func publishSoon() {
        guard enabled, cloud != nil else { return }
        pendingPublish?.cancel()
        pendingPublish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.publish(force: false)
                self.problem = nil
            } catch {
                self.problem = Self.describe(error)
            }
        }
    }

    /// Removes this Mac from the user's phones.
    private func withdraw() async {
        pendingPublish?.cancel()
        lastSent = nil
        lastPublished = nil
        problem = nil
        try? await cloud?.delete([macID])
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
        guard enabled else { return .init(.unavailable, String(localized: "iPhone access is off on this Mac.")) }
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
        }
    }

    private func setLowPower(_ request: RemoteRequest) async -> RemoteFailure? {
        guard let policy = request.lowPowerPolicy else {
            return .init(.invalidRequest, String(localized: "Choose a supported Low Power Mode setting."))
        }
        let setting: LowPowerModeSetting = switch policy {
        case .never: .never
        case .onlyOnBattery: .onlyOnBattery
        case .onlyOnAdapter: .onlyOnPowerAdapter
        case .always: .always
        }
        // A phone may change a setting through an installed helper, never install or repair one.
        helper.refreshStatus()
        guard helper.canApply, !helper.isOutdated else {
            return .init(.helperUnavailable, String(localized: "Set up the power helper on the Mac first: start closed-lid Keep Awake there once."))
        }
        do {
            try await helper.apply(.lowPowerMode(setting))
            cachedPower = nil
        } catch {
            return .init(.helperUnavailable, String(localized: "Set up the power helper on the Mac first: start closed-lid Keep Awake there once."))
        }
        let verified = await PowerSettingsReader.fetch()
        guard PowerChange.lowPowerMode(setting).isReflected(in: verified) else {
            return .init(.startFailed, String(localized: "macOS did not apply the Low Power Mode change."))
        }
        return nil
    }

    private func sleepDisplay() async -> RemoteFailure? {
        do {
            _ = try await BoundedCommand.run(
                executable: "/usr/bin/pmset",
                arguments: ["displaysleepnow"],
                timeout: 5,
                maximumOutputBytes: 16_384
            )
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
            return .init(.invalidRequest, String(localized: "Choose a supported mode and duration."))
        }
        guard !awake.isActive, !awake.isChanging, !awake.isAwaitingHelperApproval else {
            return .init(.busy, String(localized: "Keep Awake is already running or changing. Stop it first."))
        }
        if mode == .lidClosed {
            guard closedLidAllowed else {
                return .init(.closedLidNotAllowed, String(localized: "Allow closed-lid sessions from iPhone in Battistics on the Mac."))
            }
            do {
                try await helper.prepareForLidSleep()
            } catch {
                return .init(.helperUnavailable, String(localized: "Set up the power helper on the Mac first: start closed-lid Keep Awake there once."))
            }
        }
        let id = UUID().uuidString
        let name = request.deviceName.map { String($0.prefix(64)) }.flatMap { $0.isEmpty ? nil : $0 }
        let task = awake.start(mode: mode, duration: duration, id: id, allowHelperSetup: false,
                               name: name ?? String(localized: "iPhone"), origin: .phone)
        await task?.value
        guard awake.sessionIdentifier == id, awake.isActive else {
            let message = awake.errorMessage ?? String(localized: "Keep Awake could not start.")
            return .init(awake.safety.blockingEvent() == nil ? .startFailed : .protection, message)
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
        var status = status()
        async let historyTask = chargeHistory()
        let power = await powerSettings()
        let history = await historyTask
        status.chargeHistory = history.isEmpty ? nil : history
        if let power, var battery = status.battery {
            battery.lowPowerPolicy = switch power.lowPowerMode {
            case .never: .never
            case .onlyOnBattery: .onlyOnBattery
            case .onlyOnPowerAdapter: .onlyOnAdapter
            case .always: .always
            case nil: nil
            }
            if let sourceActive = battery.onAdapter ? power.ac?.lowPowerMode : power.battery?.lowPowerMode {
                battery.lowPowerMode = sourceActive
            }
            status.battery = battery
        }
        return status
    }

    func status(at now: Date = Date()) -> RemoteStatus {
        let snapshot = BatteryReader.read()
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
                rawMaxCapacityMah: snapshot.rawMaxCapacity > 0 ? snapshot.rawMaxCapacity : nil,
                designCapacityMah: snapshot.designCapacity > 0 ? snapshot.designCapacity : nil,
                voltageMV: snapshot.voltageMV,
                amperageMA: snapshot.amperageMA,
                adapterName: snapshot.adapter?.name,
                adapterVoltageMV: snapshot.adapter?.voltageMV,
                adapterAmperageMA: snapshot.adapter?.amperageMA,
                manufactureDate: snapshot.manufactureDate,
                serialNumber: snapshot.serialNumber
            )
        }
        let session = awake.session.map { session in
            RemoteStatus.Session(
                mode: RemoteStatus.Mode(rawValue: session.mode.rawValue) ?? .displayMaySleep,
                origin: awake.sessionOrigin, name: automation.activeTaskName ?? awake.sessionName,
                startedAt: session.startedAt, deadline: session.deadline)
        }
        let protection = awake.safety.configuration
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "macOS \(osVer.majorVersion).\(osVer.minorVersion)\(osVer.patchVersion > 0 ? ".\(osVer.patchVersion)" : "")"
        return RemoteStatus(
            machineName: Host.current().localizedName ?? "Mac",
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
                stopOnThermal: protection.stopOnThermalPressure,
                closedLidAllowed: closedLidAllowed
            ),
            macModel: Self.macHardwareModel(),
            osVersion: osString,
            pairedPhoneName: network.preferredHotspotPhoneName,
            heartbeatSeconds: RemoteStatus.heartbeat(duringSession: session != nil)
        )
    }

    private static func macHardwareModel() -> String? {
        var size: Int = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let raw = buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) } ?? ""
        }
        guard !raw.isEmpty else { return nil }
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
