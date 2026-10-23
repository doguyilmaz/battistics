import AppKit
import BattisticsCore
import BattisticsRemote
import SwiftUI

extension Notification.Name {
    static let battisticsSelectPane = Notification.Name("battisticsSelectPane")
}

/// Serves the phone protocol on loopback with a temporary port. Takes only
/// short-lived idle/display assertions; never installs the helper.
@main
@MainActor
struct RemoteHarness {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.setVolatileDomain([
            Prefs.keepAwakeWarnOnLowBattery: false, Prefs.keepAwakeStopOnLowBattery: false,
            Prefs.keepAwakeStopOnThermalPressure: false, Prefs.remoteEnabled: true,
            Prefs.remoteClosedLidAllowed: false, Prefs.remoteDevices: Data("[]".utf8),
            Prefs.powerSamplingEnabled: false, Prefs.hasSeenTour: true,
        ], forName: UserDefaults.argumentDomain)
        Prefs.registerDefaults()
        let helper = PowerHelperClient()
        let awake = KeepAwakeModel(helper: helper)
        let automation = AutomationModel(awake: awake, helper: helper,
                                         endpoint: .init(directory: "/private/tmp/battistics-remote-\(UUID())"),
                                         initiallyEnabled: false)
        let network = NetworkMonitor()
        let port = UInt16.random(in: 50_000...60_000)
        let remote = RemoteAccessModel(awake: awake, automation: automation, helper: helper, network: network,
                                       port: port, extraHosts: ["127.0.0.1"])
        try await eventually { remote.addresses.contains("127.0.0.1") }
        if let path = ProcessInfo.processInfo.environment["BATTISTICS_REMOTE_SERVE"] {
            try await serve(remote, awake: awake, pairingFile: path)
        }

        remote.startPairing()
        let invite = try require(remote.invite)
        precondition(invite.pairing.port == port && RemotePairing(url: invite.pairing.url) == invite.pairing)
        let phone = RemotePairing(name: invite.pairing.name, host: "127.0.0.1", port: port, token: invite.pairing.token)
        func send(_ operation: RemoteRequest.Operation, mode: RemoteStatus.Mode? = nil, minutes: Int? = nil,
                  as pairing: RemotePairing = phone) async throws -> RemoteReply {
            try await RemoteClient.send(.init(token: pairing.token, operation: operation, mode: mode,
                                              durationMinutes: minutes, deviceName: "Test iPhone"), to: pairing)
        }

        let first = try await send(.status)
        precondition(first.status?.session == nil && remote.invite == nil)
        precondition(remote.devices.first?.name == "Test iPhone" && remote.devices.first?.lastSeen != nil)

        let unbounded = try await send(.start, mode: .displayMaySleep, minutes: 0)
        precondition(unbounded.error?.code == .invalidRequest && !awake.isActive)
        let closedLid = try await send(.start, mode: .lidClosed, minutes: 15)
        precondition(closedLid.error?.code == .closedLidNotAllowed && !awake.isActive)

        let started = try await send(.start, mode: .displayMaySleep, minutes: 15)
        let session = try require(started.status?.session)
        precondition(session.origin == .phone && session.name == "Test iPhone" && awake.sessionOrigin == .phone)
        precondition(session.deadline.map { abs($0.timeIntervalSinceNow - 900) < 5 } == true)
        let again = try await send(.start, mode: .displayOn, minutes: 30)
        precondition(again.error?.code == .busy && awake.session?.mode == .displayMaySleep)

        let stopped = try await send(.stop)
        precondition(stopped.status?.session == nil && stopped.status?.lastEnd?.reason == .phone && !awake.isActive)

        let stranger = RemotePairing(name: "Mac", host: "127.0.0.1", port: port, token: RemotePairing.makeToken())
        let denied = try await send(.status, as: stranger)
        precondition(denied.error?.code == .unauthorized && denied.status == nil)

        remote.remove(try require(remote.devices.first))
        let removed = try await send(.status)
        precondition(removed.error?.code == .unauthorized)

        remote.enabled = false
        try await eventually { remote.addresses.isEmpty }
        do {
            _ = try await RemoteClient.send(.init(token: phone.token, operation: .status), to: phone, timeout: .seconds(2))
            preconditionFailure("A disabled server answered")
        } catch {}
        print("PASS: pairing, status, start limits, busy, phone stop reason, unauthorized, unpair, disable")
    }

    /// Keeps serving for manual checks from the iOS Simulator, which shares
    /// this Mac's loopback. Writes the pairing link to `pairingFile`.
    private static func serve(_ remote: RemoteAccessModel, awake: KeepAwakeModel, pairingFile: String) async throws -> Never {
        remote.startPairing()
        let url = try require(remote.invite).pairing.url.absoluteString
        try url.write(toFile: pairingFile, atomically: true, encoding: .utf8)
        print(url)
        while true {
            try await Task.sleep(for: .seconds(60))
            if remote.invite == nil, remote.devices.isEmpty { remote.startPairing() }
        }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }

    private static func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(predicate(), "Expected a transition within three seconds")
    }
}
