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
        /// Whether the Mac reported recently enough to count as awake.
        var reachable: Bool
    }

    private(set) var readings: [String: Reading]
    private(set) var refreshing = false
    /// The command each Mac is waiting on, so only the control that sent it shows progress.
    private(set) var pending: [String: RemoteRequest.Operation] = [:]
    /// Why iCloud could not be read, in the user's language.
    private(set) var problem: String?
    var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "selectedMac")
            WidgetBridge.publish(selected, reading: selected.flatMap { readings[$0.id] })
        }
    }

    var isLocalPhoneSelected: Bool {
        selectedID == Self.localPhoneID
    }

    @ObservationIgnored private lazy var cloud = RemoteCloud()
    @ObservationIgnored private var alertSubscriptionChecked: Date?

    private init() {
        readings = UserDefaults.standard.data(forKey: "readings")
            .flatMap { try? RemoteWire.decode([String: Reading].self, from: $0) } ?? [:]
        selectedID = UserDefaults.standard.string(forKey: "selectedMac")
        #if DEBUG
        if DemoData.isEnabled { readings = DemoData.readings }
        #endif
        RemoteIntentBridge.start = { [weak self] mode, minutes in
            guard let self, let mac = self.selected else { return }
            await Notifications.report(await self.start(mac, mode: mode, minutes: minutes), for: mac)
        }
        RemoteIntentBridge.stop = { [weak self] id in
            guard let self, let mac = self.mac(id) else { return }
            await Notifications.report(await self.stop(mac), for: mac)
        }
        RemoteIntentBridge.extend = { [weak self] id, minutes in
            guard let self, let mac = self.mac(id) else { return }
            await Notifications.report(await self.extend(mac, minutes: minutes), for: mac)
        }
        WidgetBridge.publish(selected, reading: selected.flatMap { readings[$0.id] })
    }

    var macs: [Mac] {
        readings.compactMap { id, reading in reading.status.map { Mac(id: id, name: $0.machineName) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selected: Mac? { macs.first { $0.id == selectedID } ?? macs.first }

    /// The Mac a widget or Live Activity names, else the selected one.
    private func mac(_ id: String?) -> Mac? {
        id.flatMap { id in macs.first { $0.id == id } } ?? selected
    }

    func reading(for mac: Mac) -> Reading? { readings[mac.id] }

    // MARK: Reading

    /// Reads every Mac and returns the alerts their changes call for.
    @discardableResult
    func refreshAll() async -> [(Mac, [RemoteAlert])] {
        // A push during a refresh may carry a newer change, and its handler
        // must not complete before that change is read.
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return [] }
        }
        #if DEBUG
        if DemoData.isEnabled { return [] }
        #endif
        refreshing = true
        defer { refreshing = false }
        let snapshot: RemoteCloud.Snapshot
        do {
            snapshot = try await cloud.fetch()
            problem = nil
        } catch {
            if !Task.isCancelled { problem = Self.describe(error) }
            return []
        }
        // A cancelled refresh says nothing about the Macs.
        guard !Task.isCancelled else { return [] }
        if alertSubscriptionChecked.map({ -$0.timeIntervalSinceNow > 600 }) ?? true {
            alertSubscriptionChecked = .now
            Task { await syncAlertSubscription() }
        }
        return await apply(snapshot)
    }

    private func apply(_ snapshot: RemoteCloud.Snapshot) async -> [(Mac, [RemoteAlert])] {
        var alerts: [(Mac, [RemoteAlert])] = []
        for (id, status) in snapshot.statuses {
            let previous: RemoteStatus?? = readings[id].map { $0.reachable ? $0.status : nil }
            let fresh = status.isFresh()
            let reading = Reading(status: status, reachable: fresh)
            readings[id] = reading
            let mac = Mac(id: id, name: status.machineName)
            let pushed = status.pushesAlerts == true && UserDefaults.standard.bool(forKey: Notifications.pushedKey)
            let macAlerts = RemoteAlert.alerts(from: previous, to: fresh ? status : nil,
                                               chargeTarget: Notifications.chargeTarget)
                .filter { !pushed || !RemoteAlert.pushedKinds.contains($0.kind) }
            alerts.append((mac, macAlerts))
            Notifications.syncWatchdog(for: mac, reading: reading)
        }
        // A Mac that stopped sharing is gone, not silent.
        for id in readings.keys where snapshot.statuses[id] == nil && !snapshot.unreadable.contains(id) {
            readings[id] = nil
            Notifications.syncWatchdog(for: Mac(id: id, name: ""), reading: nil)
        }
        save()
        await WidgetBridge.settle()
        LocalPhoneMonitor.shared.learnHotspotName(from: readings)
        // Awaited so a background task does not complete before the alerts are added.
        await Notifications.deliver(alerts)
        return alerts
    }

    /// Keeps iCloud's alert subscription in step with the Notifications
    /// switch. The subscription belongs to the account, so it is checked on
    /// the server rather than remembered: another phone, or iCloud recreating
    /// the zone, can remove it. Until it is confirmed, this phone raises every
    /// alert itself.
    func syncAlertSubscription() async {
        alertSubscriptionChecked = .now
        let wanted = UserDefaults.standard.object(forKey: Notifications.enabledKey) as? Bool ?? true
        do {
            if wanted {
                if try await !cloud.hasAlertSubscription() { try await cloud.subscribeToAlerts() }
            } else {
                try await cloud.unsubscribeFromAlerts()
            }
            UserDefaults.standard.set(wanted, forKey: Notifications.pushedKey)
        } catch {
            UserDefaults.standard.set(false, forKey: Notifications.pushedKey)
        }
    }

    /// For a Mac that was erased or sold. One that still shares publishes
    /// again as soon as it sees its record gone.
    func forget(_ mac: Mac) async -> String? {
        // A refresh already under way would put the Mac back after this.
        while refreshing { try? await Task.sleep(for: .milliseconds(200)) }
        refreshing = true
        defer { refreshing = false }
        do {
            try await cloud.delete([mac.id])
        } catch {
            return Self.describe(error)
        }
        readings[mac.id] = nil
        Notifications.syncWatchdog(for: mac, reading: nil)
        save()
        return nil
    }

    // MARK: Commands

    /// Returns a message to show when the Mac refused or did not answer.
    func start(_ mac: Mac, mode: RemoteStatus.Mode, minutes: Int) async -> String? {
        await send(.init(operation: .start, mode: mode, durationMinutes: minutes, deviceName: LocalPhoneMonitor.shared.commandName), to: mac)
    }

    func stop(_ mac: Mac) async -> String? {
        await send(.init(operation: .stop, deviceName: LocalPhoneMonitor.shared.commandName), to: mac)
    }

    func extend(_ mac: Mac, minutes: Int) async -> String? {
        await send(.init(operation: .extend, durationMinutes: minutes, deviceName: LocalPhoneMonitor.shared.commandName), to: mac)
    }

    func setLowPower(_ mac: Mac, policy: RemoteStatus.LowPowerPolicy) async -> String? {
        await send(.init(operation: .setLowPower, lowPowerPolicy: policy, deviceName: LocalPhoneMonitor.shared.commandName), to: mac)
    }

    func sleepDisplay(_ mac: Mac) async -> String? {
        await send(.init(operation: .sleepDisplay, deviceName: LocalPhoneMonitor.shared.commandName), to: mac)
    }

    func inspect(_ mac: Mac) async -> String? {
        await send(.init(operation: .inspect, deviceName: LocalPhoneMonitor.shared.commandName), to: mac)
    }

    /// Writes the command, then watches the Mac's record for its answer.
    private func send(_ request: RemoteRequest, to mac: Mac) async -> String? {
        let locks = request.operation != .inspect
        if locks { pending[mac.id] = request.operation }
        defer { if locks { pending[mac.id] = nil } }
        #if DEBUG
        if DemoData.isEnabled, var status = readings[mac.id]?.status {
            try? await Task.sleep(for: .seconds(request.operation == .inspect ? 2 : 0.6))
            DemoData.apply(request, to: &status)
            readings[mac.id] = .init(status: status, reachable: true)
            return nil
        }
        #endif
        do {
            _ = try await cloud.send(request, to: mac.id)
        } catch {
            return Self.describe(error)
        }
        // Long enough for an idle Mac's poll, its fetch and its write.
        for _ in 0..<24 {
            do { try await Task.sleep(for: .seconds(1.5)) } catch { break }
            // Through refreshAll, so this read and a push's never apply out of order.
            await refreshAll()
            if let result = readings[mac.id]?.status?.lastCommand, result.id == request.id {
                return result.failure.map(Self.message)
            }
        }
        // Never run a command the user has stopped waiting for, also when the
        // caller was cancelled, which would cancel a delete made in its task.
        let cloud = cloud
        await Task { try? await cloud.delete([request.id]) }.value
        return String(localized: "\(mac.name) did not answer. It may be asleep or offline.")
    }

    private func save() {
        UserDefaults.standard.set(try? RemoteWire.encode(readings), forKey: "readings")
        WidgetBridge.publish(selected, reading: selected.flatMap { readings[$0.id] })
        QuickActions.update(selected.flatMap { readings[$0.id] })
    }

    /// In this iPhone's language; the Mac's own text may be in another.
    private static func message(_ failure: RemoteFailure) -> String {
        switch failure.code {
        case .invalidRequest: String(localized: "Update Battistics on the Mac or this app.")
        case .busy: String(localized: "Keep Awake is already running or changing on the Mac.")
        case .closedLidNotAllowed: String(localized: "Allow closed-lid sessions from iPhone in Battistics on the Mac.")
        case .helperUnavailable: String(localized: "Set up or repair the power helper in Battistics › Power on the Mac.")
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
