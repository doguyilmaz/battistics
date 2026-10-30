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
    private static let removalPendingKey = "alertSubscriptionRemovalPending"

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
    /// Until this launch's first successful read, a saved reading too old to be
    /// live says nothing about the Mac, so it shows as updating, not offline.
    private(set) var checking = true
    /// Progress is not an error and must not make the status indicator orange.
    private(set) var waitingForUpdate = false
    private(set) var commandDiagnostic: String?
    /// Macs whose status is too new for this app to read.
    private(set) var outdated: Set<String> = []
    var selectedID: String? {
        didSet {
            if selectedID != Self.localPhoneID { macID = selectedID }
            if !isSample { UserDefaults.standard.set(selectedID, forKey: "selectedMac") }
            publishSelected()
        }
    }
    /// The Mac that widgets, Siri and the Live Activity act on. Looking at
    /// This iPhone keeps it, so they never switch to another Mac.
    private var macID: String? {
        didSet { if !isSample { UserDefaults.standard.set(macID, forKey: "remoteMac") } }
    }
    /// Trying the app with made-up Macs, held in memory only.
    private(set) var isSample = DemoData.isEnabled

    var isLocalPhoneSelected: Bool {
        selectedID == Self.localPhoneID
    }

    @ObservationIgnored private lazy var cloud = RemoteCloud()
    @ObservationIgnored private var reader: RemoteRead<RemoteCloud.Snapshot>?
    @ObservationIgnored private var subscriptionWork: Task<Void, Never>?
    @ObservationIgnored private var alertSubscriptionChecked: Date?
    @ObservationIgnored private var sending: Set<String> = []
    @ObservationIgnored private var commandAnsweredAt: [String: Date] = [:]
    @ObservationIgnored private var lastConnectionIssue = "none"
    /// The Macs Siri and Spotlight last offered by name.
    @ObservationIgnored private var shortcutMacs: [Mac] = []

    private init() {
        readings = DemoData.isEnabled ? DemoData.readings : Self.savedReadings()
        // Before selectedID, whose didSet already publishes the Mac to widgets.
        let saved = UserDefaults.standard.string(forKey: "selectedMac")
        macID = UserDefaults.standard.string(forKey: "remoteMac") ?? (saved == Self.localPhoneID ? nil : saved)
        selectedID = saved
        RemoteIntentBridge.start = { [weak self] id, mode, minutes in
            guard let self else { return }
            guard let mac = self.mac(id) else { return await Notifications.reportNoMac() }
            self.follow(mac)
            await Notifications.report(await self.start(mac, mode: mode, minutes: minutes), for: mac)
        }
        RemoteIntentBridge.stop = { [weak self] id in
            guard let self, let mac = self.mac(id) else { return }
            await Notifications.report(await self.stop(mac), for: mac)
        }
        RemoteIntentBridge.sleepDisplay = { [weak self] in
            guard let self else { return }
            guard let mac = self.remoteMac else { return await Notifications.reportNoMac() }
            await Notifications.report(await self.sleepDisplay(mac), for: mac)
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

    var selected: Mac? { macs.first { $0.id == macID } ?? macs.first }

    /// The Mac Siri, Shortcuts, widgets and the Live Activity act on; never a
    /// sample tried in the app.
    var remoteMac: Mac? { triesSample ? nil : selected }

    private var triesSample: Bool { isSample && !DemoData.isEnabled }

    var remoteMacs: [Mac] { triesSample ? [] : macs }

    /// Widgets move to a Mac a Shortcut, widget or control starts or extends.
    func follow(_ mac: Mac) {
        guard mac.id != macID else { return }
        if isLocalPhoneSelected {
            macID = mac.id
            publishSelected()
        } else {
            selectedID = mac.id
        }
    }

    /// A Mac picked in Shortcuts, else `remoteMac`.
    func remoteMac(id: String?) -> Mac? {
        guard let id else { return remoteMac }
        return remoteMacs.first { $0.id == id }
    }

    /// The Mac a widget or Live Activity names, else the selected one.
    private func mac(_ id: String?) -> Mac? {
        guard !triesSample else { return nil }
        guard let id else { return selected }
        return macs.first { $0.id == id }
    }

    func reading(for mac: Mac) -> Reading? { readings[mac.id] }

    /// Shows a Mac from a widget, an alert or Shortcuts, leaving a sample tried in the app.
    @discardableResult
    func select(_ id: String) -> Bool {
        if triesSample, Self.savedReadings()[id] != nil { endSample() }
        guard macs.contains(where: { $0.id == id }) else { return false }
        selectedID = id
        return true
    }

    /// `battistics-remote://mac/<ID>`, from a widget or the Live Activity.
    func open(_ url: URL) {
        guard url.scheme == "battistics-remote", url.host() == "mac" else { return }
        select(url.lastPathComponent)
    }

    /// Alerts are named "<Mac ID>.<kind>", here and in the Mac's pushes.
    func show(notification identifier: String) {
        if let dot = identifier.lastIndex(of: ".") { select(String(identifier[..<dot])) }
    }

    func isShowing(alert identifier: String) -> Bool {
        guard !isLocalPhoneSelected, let dot = identifier.lastIndex(of: ".") else { return false }
        return selected?.id == String(identifier[..<dot])
    }

    // MARK: Sample

    func showSample() {
        isSample = true
        problem = nil
        readings = DemoData.readings
        selectedID = DemoData.firstID
    }

    func endSample() {
        isSample = false
        readings = Self.savedReadings()
        macID = UserDefaults.standard.string(forKey: "remoteMac")
        selectedID = UserDefaults.standard.string(forKey: "selectedMac")
        Task { await refreshAll() }
    }

    /// A reading saved as live counts only while it is still fresh, so an
    /// offline launch does not show an old one as current.
    private static func savedReadings() -> [String: Reading] {
        let saved = UserDefaults.standard.data(forKey: "readings")
            .flatMap { try? RemoteWire.decode([String: Reading].self, from: $0) } ?? [:]
        return saved.mapValues { .init(status: $0.status, reachable: $0.reachable && $0.status?.isFresh() == true) }
    }

    // MARK: Reading

    /// Reads every Mac and returns the alerts their changes call for.
    @discardableResult
    func refreshAll() async -> [(Mac, [RemoteAlert])] {
        // A push during a refresh may carry a newer change, and its handler
        // must not complete before that change is read.
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return [] }
        }
        if isSample { return [] }
        refreshing = true
        defer { refreshing = false }
        let snapshot: RemoteCloud.Snapshot
        waitingForUpdate = false
        let slow = Task { [weak self] in
            try? await Task.sleep(for: Self.slowRead)
            guard !Task.isCancelled else { return }
            self?.waitingForUpdate = true
        }
        defer { slow.cancel(); waitingForUpdate = false }
        do {
            snapshot = try await readSnapshot()
            slow.cancel()
            problem = nil
            lastConnectionIssue = "none"
        } catch is CancellationError {
            lastConnectionIssue = "waiter-cancelled"
            return []
        } catch {
            guard !isSample else { return [] }
            lastConnectionIssue = Self.diagnosticError(error)
            problem = Self.describe(error)
            return []
        }
        // One that ended after the sample replaced the Macs says nothing about them.
        guard !isSample else { return [] }
        checking = false
        let subscriptionDue = alertSubscriptionChecked.map { -$0.timeIntervalSinceNow > 120 } ?? true
        let alerts = await apply(snapshot)
        // Notification housekeeping is independent of readings and commands.
        // Until confirmed, this phone retains the existing local-alert fallback.
        if subscriptionDue, subscriptionWork == nil {
            subscriptionWork = Task { [weak self] in
                await self?.syncAlertSubscription()
                self?.subscriptionWork = nil
            }
        }
        return alerts
    }

    private func readSnapshot() async throws -> RemoteCloud.Snapshot {
        let active: RemoteRead<RemoteCloud.Snapshot>
        if let reader {
            active = reader
        } else {
            let cloud = cloud
            active = RemoteRead(timeout: .seconds(45)) {
                try await cloud.fetch(until: .now.advanced(by: .seconds(45)))
            }
            reader = active
        }
        return try await active.value()
    }

    /// Only the user-triggered copy action calls this. Reading diagnostics does
    /// not refresh iCloud or include names, record IDs, network names or payloads.
    func copyConnectionDetails() async {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let header = "Battistics Remote \(version) (\(build))\n" +
            "checking=\(checking) refreshing=\(refreshing) savedMacs=\(readings.count)\n" +
            "lastRefresh=\(lastConnectionIssue)\n" +
            "lastCommand=\(commandDiagnostic ?? (pending.isEmpty ? "none" : "pending"))\n"
        let details = isSample ? "sample-data; no iCloud request" : await cloud.connectionReport()
        UIPasteboard.general.string = header + details
    }

    private func apply(_ snapshot: RemoteCloud.Snapshot) async -> [(Mac, [RemoteAlert])] {
        var alerts: [(Mac, [RemoteAlert])] = []
        // Also a Mac never read before, so setup can say why it does not appear.
        outdated = snapshot.unreadable
        for (id, status) in snapshot.statuses {
            // A direct command answer may have arrived while discovery ran.
            if let current = readings[id]?.status, current.readAt > status.readAt { continue }
            let previous: RemoteStatus?? = readings[id].map { $0.reachable ? $0.status : nil }
            let fresh = status.isFresh()
            let reading = Reading(status: status, reachable: fresh)
            readings[id] = reading
            let mac = Mac(id: id, name: status.machineName)
            let pushed = UserDefaults.standard.bool(forKey: Notifications.pushedKey)
            let macAlerts = Notifications.latchCharge(
                // A Mac that said it is going to sleep is not silent.
                RemoteAlert.alerts(from: previous, to: fresh || status.sleptAt != nil ? status : nil,
                                   chargeTarget: Notifications.chargeTarget),
                macID: id, status: fresh ? status : nil)
                .filter { !pushed || !RemoteAlert.pushedKinds.contains($0.kind) }
            alerts.append((mac, macAlerts))
            Notifications.syncWatchdog(for: mac, reading: reading)
        }
        // Its last readable status stays, but no longer as live.
        for id in snapshot.unreadable where readings[id] != nil {
            readings[id]?.reachable = false
        }
        // A Mac that stopped sharing is gone, not silent.
        for id in readings.keys where snapshot.statuses[id] == nil && !snapshot.unreadable.contains(id) {
            if commandAnsweredAt[id].map({ $0 > snapshot.requestedAt }) == true { continue }
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
    /// alert itself. Only turning the switch off removes it; a routine check
    /// never does, since another iPhone on the account may still want it.
    func syncAlertSubscription(removing: Bool = false) async {
        // Sample controls must not contact or change the real iCloud account.
        guard !isSample else { return }
        alertSubscriptionChecked = .now
        let wanted = Notifications.isEnabled
        let defaults = UserDefaults.standard
        // Kept until iCloud confirms, so an offline switch-off is retried.
        if removing { defaults.set(true, forKey: Self.removalPendingKey) }
        do {
            if wanted {
                defaults.set(false, forKey: Self.removalPendingKey)
                let subscribed = try await cloud.hasAlertSubscription()
                if !subscribed {
                    try await cloud.subscribeToAlerts()
                    // Confirmed by the next refresh, which then leaves the Mac's alerts to iCloud.
                    alertSubscriptionChecked = nil
                }
                // What the Mac posted while it was missing never reached this iPhone.
                UserDefaults.standard.set(subscribed, forKey: Notifications.pushedKey)
            } else {
                if defaults.bool(forKey: Self.removalPendingKey) {
                    try await cloud.unsubscribeFromAlerts()
                    defaults.set(false, forKey: Self.removalPendingKey)
                }
                UserDefaults.standard.set(false, forKey: Notifications.pushedKey)
            }
        } catch {
            UserDefaults.standard.set(false, forKey: Notifications.pushedKey)
        }
    }

    /// For a Mac that was erased or sold. One that still shares publishes
    /// again as soon as it sees its record gone.
    func forget(_ mac: Mac) async -> String? {
        // A refresh already under way would put the Mac back after this.
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return String(localized: "Cancelled.") }
        }
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
        await send(.init(operation: .start, mode: mode, durationMinutes: minutes), to: mac)
    }

    func stop(_ mac: Mac) async -> String? {
        await send(.init(operation: .stop), to: mac)
    }

    func extend(_ mac: Mac, minutes: Int) async -> String? {
        await send(.init(operation: .extend, durationMinutes: minutes), to: mac)
    }

    func setLowPower(_ mac: Mac, policy: RemoteStatus.LowPowerPolicy) async -> String? {
        await send(.init(operation: .setLowPower, lowPowerPolicy: policy), to: mac)
    }

    func sleepDisplay(_ mac: Mac) async -> String? {
        await send(.init(operation: .sleepDisplay), to: mac)
    }

    func sleep(_ mac: Mac) async -> String? {
        await send(.init(operation: .sleep), to: mac)
    }

    func inspect(_ mac: Mac) async -> String? {
        await send(.init(operation: .inspect), to: mac)
    }

    /// Writes the command, then watches the Mac's record for its answer.
    private func send(_ request: RemoteRequest, to mac: Mac) async -> String? {
        var request = request
        guard !sending.contains(mac.id) else {
            return String(localized: "Wait for the current change to finish.", table: "RemoteSync")
        }
        commandDiagnostic = nil
        request.deviceName = LocalPhoneMonitor.shared.commandName
        // A second change to the same Mac is refused, not queued indefinitely.
        let locks = request.operation != .inspect
        if locks { pending[mac.id] = request.operation }
        defer { if locks, pending[mac.id] == request.operation { pending[mac.id] = nil } }
        sending.insert(mac.id)
        defer { sending.remove(mac.id) }
        request.sentAt = .now
        if isSample, var status = readings[mac.id]?.status {
            try? await Task.sleep(for: .seconds(request.operation == .inspect ? 2 : 0.6))
            guard isSample else { return nil }
            DemoData.apply(request, to: &status)
            readings[mac.id] = .init(status: status, reachable: true)
            publishSelected()
            return nil
        }
        do {
            let status = try await RemoteCommandExecutor.execute(request, to: mac.id, cloud: cloud)
            commandAnsweredAt[mac.id] = .now
            if readings[mac.id]?.status.map({ $0.readAt <= status.readAt }) ?? true {
                let reading = Reading(status: status, reachable: status.isFresh())
                readings[mac.id] = reading
                Notifications.syncWatchdog(for: mac, reading: reading)
                save()
            }
            if let failure = status.lastCommand?.failure {
                commandDiagnostic = "remote-refusal \(failure.code.rawValue)"
                return Self.message(failure)
            }
            return nil
        } catch is CancellationError {
            commandDiagnostic = "cancelled"
            return String(localized: "Cancelled.")
        } catch is RemoteDeadline.Failure {
            commandDiagnostic = "deadline"
            return String(localized: "The change wasn't confirmed. Check your Mac's status before trying again.", table: "RemoteSync")
        } catch {
            commandDiagnostic = Self.diagnosticError(error)
            return Self.describe(error)
        }
    }

    private func save() {
        UserDefaults.standard.set(try? RemoteWire.encode(readings), forKey: "readings")
        publishSelected()
    }

    /// Hands the selected Mac to widgets, the Live Activity and quick actions.
    func publishSelected() {
        // A sample tried in the app stays out of widgets and the Lock Screen;
        // `-demo` screenshots need them.
        if triesSample { return }
        WidgetBridge.publish(selected, reading: selected.flatMap { readings[$0.id] })
        WidgetBridge.publishAll(macs.map { SharedSnapshot($0, reading: readings[$0.id]) })
        WidgetBridge.syncActivities(macs.map { ($0, readings[$0.id]) }, confirmed: !checking)
        QuickActions.update(selected.flatMap { readings[$0.id] })
        if macs != shortcutMacs {
            shortcutMacs = macs
            Shortcuts.updateAppShortcutParameters()
        }
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

    /// Neutral progress wording; only the actual request failure is an error.
    private static let slowRead: Duration = .seconds(15)

    private static func diagnosticError(_ error: Error) -> String {
        let ns = error as NSError
        let kind = error is RemoteDeadline.Failure ? "deadline" : error is CancellationError ? "cancelled" : "framework"
        return "\(kind) \(ns.domain)/\(ns.code)"
    }

    private static func describe(_ error: Error) -> String {
        if error is RemoteDeadline.Failure {
            return String(localized: "Couldn't update right now. Check your connection and try again.", table: "RemoteSync")
        }
        return switch (error as? CKError)?.code {
        case .notAuthenticated:
            String(localized: "Sign in to iCloud on this iPhone with the same Apple Account as your Mac.")
        case .networkUnavailable, .networkFailure:
            String(localized: "This iPhone is offline.")
        case .quotaExceeded:
            String(localized: "iCloud storage is full.")
        default:
            String(localized: "iCloud could not be reached. Try again in a moment.")
        }
    }
}
