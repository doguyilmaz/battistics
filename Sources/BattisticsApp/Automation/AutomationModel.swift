import BattisticsCore
import BattisticsRemote
import Foundation
import Observation

@MainActor
@Observable
final class AutomationModel {
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Prefs.automationEnabled)
            if !enabled { stopOwnedSession() }
            reconcileListener()
        }
    }
    var closedLidAllowed: Bool {
        didSet {
            UserDefaults.standard.set(closedLidAllowed, forKey: Prefs.automationClosedLidAllowed)
            if !closedLidAllowed, ownedMode == .lidClosed { stopOwnedSession() }
        }
    }
    private(set) var isListening = false
    private(set) var errorMessage: String?
    private(set) var activeTaskName: String?
    private(set) var activeSource: AutomationRequest.Source?
    @ObservationIgnored private let awake: KeepAwakeModel
    @ObservationIgnored private let helper: PowerHelperClient
    @ObservationIgnored private let endpoint: LocalAutomationEndpoint
    @ObservationIgnored private var server: LocalAutomationServer?
    @ObservationIgnored private var connections: Set<UUID> = []
    @ObservationIgnored private var lease: AutomationLease?
    @ObservationIgnored private var ownedMode: KeepAwakeMode?
    @ObservationIgnored private var listenerTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?

    init(awake: KeepAwakeModel, helper: PowerHelperClient, endpoint: LocalAutomationEndpoint = .standard,
         initiallyEnabled: Bool? = nil) {
        self.awake = awake
        self.helper = helper
        self.endpoint = endpoint
        enabled = initiallyEnabled ?? UserDefaults.standard.bool(forKey: Prefs.automationEnabled)
        closedLidAllowed = UserDefaults.standard.bool(forKey: Prefs.automationClosedLidAllowed)
        awake.onOwnershipReleased = { [weak self] id in
            guard let self, self.lease?.id.uuidString == id else { return }
            self.clearOwnership()
        }
        reconcileListener()
    }

    func stopOwnedSession() {
        let id = lease?.id.uuidString
        clearOwnership()
        if let id, awake.sessionIdentifier == id { awake.stop(reason: .client) }
    }

    private func clearOwnership() {
        lease = nil
        ownedMode = nil
        activeTaskName = nil
        activeSource = nil
        watchdog?.cancel()
        watchdog = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }

    private func reconcileListener() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            guard let self else { return }
            defer { self.listenerTask = nil }
            repeat {
                let requested = self.enabled
                if requested, !self.isListening {
                    let server = LocalAutomationServer(endpoint: self.endpoint,
                        connected: { [weak self] in self?.connections.insert($0) },
                        disconnected: { [weak self] id in
                            guard let self else { return }
                            self.connections.remove(id)
                            if self.lease?.owner == id { self.stopOwnedSession() }
                        },
                        handler: { [weak self] id, request in
                            guard let self else { return .init(code: .unavailable, message: "Battistics has closed.") }
                            return await self.handle(request, from: id)
                        })
                    do {
                        try await server.start()
                        self.server = server
                        self.isListening = true
                        self.errorMessage = nil
                    } catch {
                        self.errorMessage = String(localized: "Could not open local automation. Close other copies of Battistics, then turn automation off and on.")
                        return
                    }
                } else if !requested {
                    if self.isListening {
                        await self.server?.stop()
                        self.server = nil
                        self.isListening = false
                    }
                    self.errorMessage = nil
                }
                if requested == self.enabled { return }
            } while true
        }
    }

    private func handle(_ request: AutomationRequest, from owner: UUID) async -> AutomationReply {
        guard enabled else { return .init(code: .disabled, message: "Enable Local automation in Battistics > Power.") }
        guard connections.contains(owner) else { return .init(code: .unavailable, message: "The client disconnected.") }
        guard request.version == 1 else { return .init(code: .invalidRequest, message: "Unsupported IPC version.") }
        if lease?.isExpired(at: Date()) == true { stopOwnedSession() }
        switch request.operation {
        case .status:
            return .init(status: status(for: owner))
        case .start:
            guard let arguments = request.validatedStart() else {
                return .init(code: .invalidRequest, message: "Provide a name of 1–80 visible characters, a supported mode, and a finite duration.")
            }
            guard lease == nil, awake.sessionIdentifier == nil, !awake.isChanging, !awake.isAwaitingHelperApproval else {
                return .init(code: .busy, message: "A Keep Awake session or helper setup is already in progress. It was left unchanged.")
            }
            if arguments.mode == .lidClosed {
                guard closedLidAllowed else { return .init(code: .closedLidNotAllowed, message: "Enable closed-lid automation in Battistics > Power first.") }
                helper.refreshStatusIfChanged()
                guard helper.isInstalled else { return .init(code: .helperUnavailable, message: "Set up the power helper in Battistics before using closed-lid automation.") }
            }
            let now = Date()
            let id = UUID()
            lease = AutomationLease(id: id, owner: owner, name: arguments.name,
                                    deadline: now.addingTimeInterval(Double(arguments.duration.rawValue) * 60), now: now)
            activeTaskName = arguments.name
            activeSource = request.source ?? .mcp
            ownedMode = arguments.mode
            startWatchdog()
            let start = awake.start(mode: arguments.mode, duration: arguments.duration, now: now,
                                    id: id.uuidString, allowHelperSetup: false,
                                    origin: request.source == .command ? .terminal : .ai)
            await start?.value
            guard enabled, connections.contains(owner), lease?.id == id,
                  awake.sessionIdentifier == id.uuidString, awake.isActive else {
                if lease?.id == id { stopOwnedSession() }
                return .init(code: .startFailed, message: awake.errorMessage ?? "The session was stopped or could not start. Check Battistics before retrying.")
            }
            return .init(status: status(for: owner))
        case .stop, .heartbeat:
            guard let id = request.sessionID else { return .init(code: .invalidRequest, message: "A session_id is required.") }
            guard let current = lease else { return .init(code: .inactive, message: "The automation session has ended. It will not be restarted.") }
            guard current.id == id, current.owner == owner else { return .init(code: .notOwner, message: "This connection does not own that session.") }
            if request.operation == .stop { stopOwnedSession() }
            else if lease?.renew(id: id, owner: owner, now: Date()) != true {
                stopOwnedSession()
                return .init(code: .inactive, message: "The automation session expired.")
            }
            return .init(status: status(for: owner))
        }
    }

    private func status(for owner: UUID) -> AutomationStatus {
        var status = AutomationStatus()
        status.active = awake.isActive
        status.mode = awake.session?.mode.rawValue
        status.deadline = awake.session?.deadline
        if awake.isActive {
            status.owner = lease.map { $0.owner == owner ? .thisClient : .anotherClient } ?? .manual
            if let lease, lease.owner == owner { status.sessionID = lease.id; status.taskName = lease.name }
        }
        if let battery = BatteryReader.read() {
            if battery.batteryInstalled { status.batteryPercent = battery.percent }
            status.powerSource = battery.externalConnected ? "adapter" : "battery"
        }
        let protection = awake.safety.configuration
        status.stopAtBatteryPercent = protection.stopOnLowBattery ? protection.effectiveStopPercent : nil
        status.batteryWarningPercent = protection.warnOnLowBattery ? protection.effectiveWarningPercent : nil
        status.stopOnThermalPressure = protection.stopOnThermalPressure
        status.closedLidAllowed = closedLidAllowed
        return status
    }

    private func startWatchdog() {
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                        reason: "Monitoring a bounded automation Keep Awake session")
        // Wakes once per heartbeat window rather than polling.
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                guard let lease = self?.lease else { return }
                let wait = min(lease.deadline, lease.heartbeatDeadline).timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(max(wait, 0) + 0.5))
                guard !Task.isCancelled, let self else { return }
                if self.lease?.isExpired(at: Date()) == true { self.stopOwnedSession(); return }
            }
        }
    }
}
