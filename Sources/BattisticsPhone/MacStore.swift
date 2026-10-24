import BattisticsRemote
import CloudKit
import Foundation
import Observation
import UIKit

/// The account's Macs as they last reported through iCloud. Shared by the
/// app, push and background refresh, and App Intents, which all run here.
@MainActor
@Observable
final class MacStore {
    static let shared = MacStore()
    static let localPhoneID = "__this_iphone__"

    struct Mac: Identifiable, Equatable {
        let id: String
        let name: String
    }

    struct Reading: Codable, Equatable {
        var status: RemoteStatus?
        var lastSeen: Date?
        /// Whether the Mac reported recently enough to count as awake.
        var reachable: Bool
    }

    private(set) var readings: [String: Reading]
    private(set) var refreshing = false
    private(set) var pending: Set<String> = []
    /// Why iCloud could not be read, in the user's language.
    private(set) var problem: String?
    var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "selectedMac")
            let widgetMac = selected ?? macs.first
            WidgetBridge.publish(widgetMac, reading: widgetMac.flatMap { readings[$0.id] })
        }
    }

    var isLocalPhoneSelected: Bool {
        selectedID == Self.localPhoneID
    }

    @ObservationIgnored private let cloud = RemoteCloud()

    private init() {
        readings = UserDefaults.standard.data(forKey: "readings")
            .flatMap { try? RemoteWire.decode([String: Reading].self, from: $0) } ?? [:]
        selectedID = UserDefaults.standard.string(forKey: "selectedMac")
        RemoteIntentBridge.startOneHour = { [weak self] in
            guard let self, let mac = self.selected else { return }
            _ = await self.start(mac, mode: .displayMaySleep, minutes: 60)
        }
        RemoteIntentBridge.stop = { [weak self] in
            guard let self, let mac = self.selected else { return }
            _ = await self.stop(mac)
        }
        WidgetBridge.publish(selected, reading: selected.flatMap { readings[$0.id] })
    }

    var macs: [Mac] {
        readings.compactMap { id, reading in reading.status.map { Mac(id: id, name: $0.machineName) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selected: Mac? { macs.first { $0.id == selectedID } ?? macs.first }

    func reading(for mac: Mac) -> Reading? { readings[mac.id] }

    // MARK: Reading

    /// Reads every Mac and returns the alerts their changes call for.
    @discardableResult
    func refreshAll() async -> [(Mac, [RemoteAlert])] {
        guard !refreshing else { return [] }
        refreshing = true
        defer { refreshing = false }
        let snapshot: RemoteCloud.Snapshot
        do {
            try await cloud.prepare()
            snapshot = try await cloud.fetch()
            problem = nil
        } catch {
            if !Task.isCancelled { problem = Self.describe(error) }
            return []
        }
        // A cancelled refresh says nothing about the Macs.
        guard !Task.isCancelled else { return [] }
        return apply(snapshot)
    }

    private func apply(_ snapshot: RemoteCloud.Snapshot) -> [(Mac, [RemoteAlert])] {
        var alerts: [(Mac, [RemoteAlert])] = []
        for (id, status) in snapshot.statuses {
            let previous: RemoteStatus?? = readings[id].map { $0.reachable ? $0.status : nil }
            let fresh = status.isFresh()
            let reading = Reading(status: status, lastSeen: status.readAt, reachable: fresh)
            readings[id] = reading
            let mac = Mac(id: id, name: status.machineName)
            let macAlerts = RemoteAlert.alerts(from: previous, to: fresh ? status : nil)
            alerts.append((mac, macAlerts))
            Notifications.syncWatchdog(for: mac, reading: reading)
        }
        // A Mac that stopped sharing is gone, not silent.
        for id in readings.keys where snapshot.statuses[id] == nil {
            readings[id] = nil
            Notifications.syncWatchdog(for: Mac(id: id, name: ""), reading: nil)
        }
        save()
        if !alerts.isEmpty {
            Task { await Notifications.deliver(alerts) }
        }
        return alerts
    }

    // MARK: Commands

    /// Returns a message to show when the Mac refused or did not answer.
    func start(_ mac: Mac, mode: RemoteStatus.Mode, minutes: Int) async -> String? {
        await send(.init(operation: .start, mode: mode, durationMinutes: minutes, deviceName: UIDevice.current.name), to: mac)
    }

    func stop(_ mac: Mac) async -> String? {
        await send(.init(operation: .stop, deviceName: UIDevice.current.name), to: mac)
    }

    func setLowPower(_ mac: Mac, policy: RemoteStatus.LowPowerPolicy) async -> String? {
        await send(.init(operation: .setLowPower, lowPowerPolicy: policy, deviceName: UIDevice.current.name), to: mac)
    }

    func sleepDisplay(_ mac: Mac) async -> String? {
        await send(.init(operation: .sleepDisplay, deviceName: UIDevice.current.name), to: mac)
    }

    /// Writes the command, then watches the Mac's record for its answer.
    private func send(_ request: RemoteRequest, to mac: Mac) async -> String? {
        pending.insert(mac.id)
        defer { pending.remove(mac.id) }
        do {
            try await cloud.prepare()
            _ = try await cloud.send(request, to: mac.id)
            for _ in 0..<16 {
                try await Task.sleep(for: .seconds(1.5))
                let snapshot = try await cloud.fetch()
                _ = apply(snapshot)
                if let result = snapshot.statuses[mac.id]?.lastCommand, result.id == request.id {
                    return result.failure.map(Self.message)
                }
            }
            // Never run a command the user has stopped waiting for.
            try? await cloud.delete([request.id])
            return String(localized: "\(mac.name) did not answer. It may be asleep or offline.")
        } catch {
            return Self.describe(error)
        }
    }

    private func save() {
        UserDefaults.standard.set(try? RemoteWire.encode(readings), forKey: "readings")
        WidgetBridge.publish(selected, reading: selected.flatMap { readings[$0.id] })
    }

    /// In this iPhone's language; the Mac's own text may be in another.
    private static func message(_ failure: RemoteFailure) -> String {
        switch failure.code {
        case .invalidRequest: String(localized: "Update Battistics on the Mac or this app.")
        case .busy: String(localized: "Keep Awake is already running or changing on the Mac.")
        case .closedLidNotAllowed: String(localized: "Allow closed-lid sessions from iPhone in Battistics on the Mac.")
        case .helperUnavailable: String(localized: "Start closed-lid Keep Awake on the Mac once to set up its helper.")
        case .protection, .startFailed: failure.message
        case .unavailable: String(localized: "iPhone access is off on the Mac.")
        }
    }

    private static func describe(_ error: Error) -> String {
        switch (error as? CKError)?.code {
        case .notAuthenticated:
            String(localized: "Sign in to iCloud on this iPhone with the same Apple ID as your Mac.")
        case .networkUnavailable, .networkFailure:
            String(localized: "This iPhone is offline.")
        default:
            String(localized: "iCloud could not be reached. Try again in a moment.")
        }
    }
}
