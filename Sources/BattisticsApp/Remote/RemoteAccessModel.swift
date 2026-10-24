import AppKit
import BattisticsCore
import BattisticsRemote
import Foundation
import Observation

/// Serves paired phones over Tailscale. Off by default; the Mac keeps only a
/// hash of each phone's token.
@MainActor
@Observable
final class RemoteAccessModel {
    struct Device: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String?
        let tokenHash: String
        let pairedAt: Date
        var lastSeen: Date?
    }

    /// A pairing shown on screen until a phone uses it or it expires.
    struct Invite: Equatable {
        let pairing: RemotePairing
        let deviceID: UUID
        let expires: Date
    }

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Prefs.remoteEnabled)
            if !enabled { cancelPairing() }
            Task { await rebind() }
        }
    }
    var closedLidAllowed: Bool {
        didSet { UserDefaults.standard.set(closedLidAllowed, forKey: Prefs.remoteClosedLidAllowed) }
    }
    private(set) var devices: [Device]
    private(set) var invite: Invite?
    private(set) var addresses: Set<String> = []

    @ObservationIgnored private let awake: KeepAwakeModel
    @ObservationIgnored private let automation: AutomationModel
    @ObservationIgnored private let helper: PowerHelperClient
    @ObservationIgnored let network: NetworkMonitor
    @ObservationIgnored private lazy var server = RemoteServer(port: port) { [weak self] request in
        guard let self else { return .init(.unavailable, "Battistics has closed.") }
        return await self.handle(request)
    }
    /// Only the newest bind may publish its addresses.
    @ObservationIgnored private var bindGeneration = 0
    @ObservationIgnored private var inviteExpiry: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private let port: UInt16
    @ObservationIgnored private let extraHosts: Set<String>
    @ObservationIgnored private let chargeHistory: @Sendable () async -> [RemoteStatus.ChargePoint]

    init(awake: KeepAwakeModel, automation: AutomationModel, helper: PowerHelperClient,
         network: NetworkMonitor, port: UInt16 = RemoteWire.defaultPort, extraHosts: Set<String>? = nil,
         chargeHistory: @escaping @Sendable () async -> [RemoteStatus.ChargePoint] = { [] }) {
        self.chargeHistory = chargeHistory
        self.awake = awake
        self.automation = automation
        self.helper = helper
        self.network = network
        self.port = port
        #if DEBUG
        self.extraHosts = extraHosts ?? (UserDefaults.standard.bool(forKey: "remoteLoopback") ? ["127.0.0.1"] : [])
        #else
        self.extraHosts = extraHosts ?? []
        #endif
        enabled = UserDefaults.standard.bool(forKey: Prefs.remoteEnabled)
        closedLidAllowed = UserDefaults.standard.bool(forKey: Prefs.remoteClosedLidAllowed)
        // An invite never used before the app quit has no expiry left to run.
        devices = (UserDefaults.standard.data(forKey: Prefs.remoteDevices))
            .flatMap { try? JSONDecoder().decode([Device].self, from: $0) }?
            .filter { $0.lastSeen != nil } ?? []
        network.onChange = { [weak self] in Task { await self?.rebind() } }
        Task { await rebind() }
    }

    /// The address a new phone should use: Tailscale first.
    private var pairingHost: String? {
        TailscaleAddress.current().sorted().first ?? extraHosts.sorted().first
    }

    func rebind() async {
        retry?.cancel()
        // Tailscale can assign its address after the network change is reported.
        if enabled, TailscaleAddress.current().isEmpty {
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.rebind()
            }
        }
        let wanted = enabled ? TailscaleAddress.current().union(extraHosts) : []
        bindGeneration += 1
        let generation = bindGeneration
        let listening = await server.listen(on: wanted)
        if generation == bindGeneration { addresses = listening }
    }

    func startPairing() {
        guard let host = pairingHost else { return }
        removeUnusedInvite()
        let token = RemotePairing.makeToken()
        let device = Device(id: UUID(), name: nil, tokenHash: RemotePairing.hash(token), pairedAt: Date())
        devices.append(device)
        save()
        let name = Host.current().localizedName ?? "Mac"
        invite = Invite(pairing: .init(name: String(name.prefix(64)), host: host, port: port, token: token),
                        deviceID: device.id, expires: Date().addingTimeInterval(600))
        inviteExpiry?.cancel()
        inviteExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.cancelPairing()
        }
    }

    func cancelPairing() {
        removeUnusedInvite()
        if let invite, NSPasteboard.general.string(forType: .string) == invite.pairing.url.absoluteString {
            NSPasteboard.general.clearContents()
        }
        invite = nil
        inviteExpiry?.cancel()
    }

    func remove(_ device: Device) {
        devices.removeAll { $0.id == device.id }
        if invite?.deviceID == device.id { invite = nil }
        save()
    }

    private func removeUnusedInvite() {
        guard let invite, devices.first(where: { $0.id == invite.deviceID })?.lastSeen == nil else { return }
        devices.removeAll { $0.id == invite.deviceID }
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(devices), forKey: Prefs.remoteDevices)
    }

    func handle(_ request: RemoteRequest) async -> RemoteReply {
        guard enabled else { return .init(.unavailable, String(localized: "Remote access is off on this Mac.")) }
        guard request.version == 1 else { return .init(.invalidRequest, String(localized: "Update Battistics on this Mac.")) }
        guard let index = devices.firstIndex(where: { RemotePairing.matches(request.token, hash: $0.tokenHash) }) else {
            return .init(.unauthorized, String(localized: "This iPhone is no longer paired. Pair it again from Battistics on the Mac."))
        }
        let name = request.deviceName.map { String($0.prefix(64)) }
        if let name, !name.isEmpty { devices[index].name = name }
        let previous = devices[index]
        devices[index].lastSeen = Date()
        if previous.lastSeen == nil, invite?.deviceID == previous.id { invite = nil; inviteExpiry?.cancel() }
        if previous.name != devices[index].name || previous.lastSeen.map({ -$0.timeIntervalSinceNow > 300 }) ?? true {
            save()
        }

        switch request.operation {
        case .status:
            return .init(status: await fullStatus())
        case .stop:
            if awake.isActive || awake.isChanging { awake.stop(reason: .phone) }
            return .init(status: await fullStatus())
        case .start:
            return await start(request, deviceName: devices[index].name)
        }
    }

    private func start(_ request: RemoteRequest, deviceName: String?) async -> RemoteReply {
        guard let minutes = request.durationMinutes, RemoteRequest.durations.contains(minutes),
              let duration = KeepAwakeDuration(rawValue: minutes),
              let mode = request.mode.flatMap({ KeepAwakeMode(rawValue: $0.rawValue) }) else {
            return .init(.invalidRequest, String(localized: "Choose a supported mode and duration."))
        }
        guard !awake.isActive, !awake.isChanging, !awake.isAwaitingHelperApproval else {
            return .init(.busy, String(localized: "Keep Awake is already running or changing. Stop it first."), status: await fullStatus())
        }
        if mode == .lidClosed {
            guard closedLidAllowed else {
                return .init(.closedLidNotAllowed, String(localized: "Allow closed-lid sessions from iPhone in Battistics on the Mac."), status: await fullStatus())
            }
            helper.refreshStatusIfChanged()
            guard helper.isInstalled else {
                return .init(.helperUnavailable, String(localized: "Set up the power helper on the Mac first: start closed-lid Keep Awake there once."), status: await fullStatus())
            }
        }
        let id = UUID().uuidString
        let task = awake.start(mode: mode, duration: duration, id: id, allowHelperSetup: false,
                               name: deviceName ?? String(localized: "iPhone"), origin: .phone)
        await task?.value
        guard awake.sessionIdentifier == id, awake.isActive else {
            let message = awake.errorMessage ?? String(localized: "Keep Awake could not start.")
            let code: RemoteReply.Code = awake.safety.blockingEvent() == nil ? .startFailed : .protection
            return .init(code, message, status: await fullStatus())
        }
        return .init(status: await fullStatus())
    }

    private func fullStatus() async -> RemoteStatus {
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
