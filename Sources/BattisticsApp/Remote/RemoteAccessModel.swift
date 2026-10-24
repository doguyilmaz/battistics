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
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var pendingPublish: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var pushObserver: NSObjectProtocol?
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
        observeSession()
        startTicker()
        if enabled, cloud != nil {
            NSApplication.shared.registerForRemoteNotifications()
            Task { await sync() }
        }
    }

    /// False for builds not signed for iCloud, such as local ad-hoc builds.
    var isAvailable: Bool { cloud != nil }

    // MARK: iCloud

    /// Runs commands addressed to this Mac, then publishes the result.
    func sync() async {
        guard enabled, let cloud, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await cloud.prepare()
            let snapshot = try await cloud.fetch()
            let mine = snapshot.commands.filter { $0.macID == macID }.sorted { $0.request.sentAt < $1.request.sentAt }
            for command in mine where -command.request.sentAt.timeIntervalSinceNow < RemoteRequest.lifetime {
                lastCommand = .init(id: command.request.id, failure: await handle(command.request))
            }
            try await cloud.delete(mine.map(\.recordName))
            try await publish(force: !mine.isEmpty)
            problem = nil
        } catch {
            problem = Self.describe(error)
        }
    }

    private func publish(force: Bool) async throws {
        guard enabled, let cloud else { return }
        var status = await fullStatus()
        status.lastCommand = lastCommand
        if !force, let lastSent, let lastPublished, -lastPublished.timeIntervalSinceNow < RemoteStatus.heartbeat {
            var compared = status
            compared.readAt = lastSent.readAt
            compared.chargeHistory = lastSent.chargeHistory
            if compared == lastSent { return }
        }
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

    /// Battery and heat change without an event: a local check each minute
    /// writes only when something differs, and a fetch every five minutes
    /// picks up a command whose push was lost.
    private func startTicker() {
        ticker = Task { [weak self] in
            var minute = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                minute += 1
                if minute % 5 == 0 { await self.sync() } else { self.publishSoon() }
            }
        }
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
        }
    }

    private func start(_ request: RemoteRequest) async -> RemoteFailure? {
        guard let minutes = request.durationMinutes, RemoteRequest.durations.contains(minutes),
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
            helper.refreshStatusIfChanged()
            guard helper.isInstalled else {
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

    func fullStatus() async -> RemoteStatus {
        var status = status()
        let history = await chargeHistory()
        status.chargeHistory = history.isEmpty ? nil : history
        return status
    }

    func status(at now: Date = Date()) -> RemoteStatus {
        let snapshot = BatteryReader.read()
        let battery = snapshot.flatMap { snapshot -> RemoteStatus.Battery? in
            guard snapshot.batteryInstalled else { return nil }
            return .init(percent: snapshot.percent, isCharging: snapshot.isCharging,
                         onAdapter: snapshot.externalConnected, minutesRemaining: snapshot.timeRemainingMin,
                         healthPercent: Int(snapshot.healthPercent.rounded()))
        }
        let session = awake.session.map { session in
            RemoteStatus.Session(
                mode: RemoteStatus.Mode(rawValue: session.mode.rawValue) ?? .displayMaySleep,
                origin: awake.sessionOrigin, name: automation.activeTaskName ?? awake.sessionName,
                startedAt: session.startedAt, deadline: session.deadline)
        }
        let protection = awake.safety.configuration
        return RemoteStatus(
            machineName: Host.current().localizedName ?? "Mac", readAt: now,
            battery: battery, session: session, lastEnd: awake.lastEnd,
            network: network.state, lidClosed: Clamshell.read()?.isClosed,
            thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
            protection: .init(
                stopAtPercent: protection.stopOnLowBattery ? protection.effectiveStopPercent : nil,
                warnAtPercent: protection.warnOnLowBattery ? protection.effectiveWarningPercent : nil,
                stopOnThermal: protection.stopOnThermalPressure, closedLidAllowed: closedLidAllowed))
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
