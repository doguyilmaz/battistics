import BattisticsRemote
import Foundation
import Observation
import UIKit

/// Paired Macs and their latest readings. Shared by the app, background
/// refresh and App Intents, which all run in this process.
@MainActor
@Observable
final class MacStore {
    static let shared = MacStore()

    struct Reading: Codable, Equatable {
        /// The last status the Mac sent, kept for display while it is silent.
        var status: RemoteStatus?
        var lastSeen: Date?
        /// Whether the most recent attempt reached the Mac.
        var reachable: Bool
    }

    private(set) var macs: [RemotePairing]
    private(set) var readings: [String: Reading]
    private(set) var refreshing: Set<String> = []
    private(set) var pending: Set<String> = []
    var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedMac") }
    }

    private init() {
        macs = Keychain.load().flatMap { try? JSONDecoder().decode([RemotePairing].self, from: $0) } ?? []
        readings = UserDefaults.standard.data(forKey: "readings")
            .flatMap { try? RemoteWire.decode([String: Reading].self, from: $0) } ?? [:]
        let saved = UserDefaults.standard.string(forKey: "selectedMac")
        selectedID = macs.contains { $0.id == saved } ? saved : macs.first?.id
    }

    var selected: RemotePairing? { macs.first { $0.id == selectedID } ?? macs.first }

    func reading(for mac: RemotePairing) -> Reading? { readings[mac.id] }

    // MARK: Pairing

    enum PairingFailure: Error { case unreachable, rejected(String) }

    /// Saves the Mac only after it answers with this token.
    func pair(_ pairing: RemotePairing) async throws {
        let reply: RemoteReply
        do { reply = try await RemoteClient.send(request(pairing, .status), to: pairing) }
        catch { throw PairingFailure.unreachable }
        guard let status = reply.status else {
            throw PairingFailure.rejected(reply.error?.message ?? String(localized: "The Mac did not accept this iPhone."))
        }
        var pairing = pairing
        pairing.name = status.machineName
        macs.removeAll { $0.host == pairing.host && $0.port == pairing.port }
        macs.append(pairing)
        saveMacs()
        selectedID = pairing.id
        record(status, for: pairing)
    }

    func remove(_ mac: RemotePairing) {
        macs.removeAll { $0.id == mac.id }
        readings[mac.id] = nil
        saveMacs()
        saveReadings()
        if selectedID == mac.id { selectedID = macs.first?.id }
    }

    // MARK: Requests

    /// Refreshes one Mac and returns the alerts its change in state calls for.
    @discardableResult
    func refresh(_ mac: RemotePairing) async -> [RemoteAlert] {
        guard !refreshing.contains(mac.id) else { return [] }
        refreshing.insert(mac.id)
        defer { refreshing.remove(mac.id) }
        let previous: RemoteStatus?? = readings[mac.id].map { $0.reachable ? $0.status : nil }
        let reply = try? await RemoteClient.send(request(mac, .status), to: mac)
        if let status = reply?.status {
            record(status, for: mac)
            return RemoteAlert.alerts(from: previous, to: status)
        }
        markUnreachable(mac)
        return RemoteAlert.alerts(from: previous, to: nil)
    }

    func refreshAll() async -> [(RemotePairing, [RemoteAlert])] {
        var result: [(RemotePairing, [RemoteAlert])] = []
        for mac in macs { result.append((mac, await refresh(mac))) }
        return result
    }

    /// Returns a message to show when the Mac refused or could not be reached.
    func start(_ mac: RemotePairing, mode: RemoteStatus.Mode, minutes: Int) async -> String? {
        await send(mac, request(mac, .start, mode: mode, minutes: minutes))
    }

    func stop(_ mac: RemotePairing) async -> String? {
        await send(mac, request(mac, .stop))
    }

    private func send(_ mac: RemotePairing, _ request: RemoteRequest) async -> String? {
        pending.insert(mac.id)
        defer { pending.remove(mac.id) }
        do {
            let reply = try await RemoteClient.send(request, to: mac)
            if let status = reply.status { record(status, for: mac) }
            return reply.error?.message
        } catch {
            markUnreachable(mac)
            return String(localized: "Could not reach \(mac.name). Check that Tailscale is on for both devices.")
        }
    }

    private func request(_ mac: RemotePairing, _ operation: RemoteRequest.Operation,
                         mode: RemoteStatus.Mode? = nil, minutes: Int? = nil) -> RemoteRequest {
        RemoteRequest(token: mac.token, operation: operation, mode: mode, durationMinutes: minutes,
                      deviceName: UIDevice.current.name)
    }

    private func record(_ status: RemoteStatus, for mac: RemotePairing) {
        readings[mac.id] = Reading(status: status, lastSeen: Date(), reachable: true)
        if let index = macs.firstIndex(where: { $0.id == mac.id }), macs[index].name != status.machineName {
            macs[index].name = status.machineName
            saveMacs()
        }
        saveReadings()
    }

    private func markUnreachable(_ mac: RemotePairing) {
        var reading = readings[mac.id] ?? Reading(reachable: false)
        reading.reachable = false
        readings[mac.id] = reading
        saveReadings()
    }

    private func saveMacs() {
        if let data = try? JSONEncoder().encode(macs) { Keychain.save(data) }
    }

    private func saveReadings() {
        UserDefaults.standard.set(try? RemoteWire.encode(readings), forKey: "readings")
    }
}
