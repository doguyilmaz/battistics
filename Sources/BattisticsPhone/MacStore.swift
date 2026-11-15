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
    @ObservationIgnored private let nearby = NearbyClient()
    @ObservationIgnored private var nearbyTrust: [String: NearbyCredential] = [:]
    @ObservationIgnored private var nearbyAccountID: String?
    @ObservationIgnored private var nearbyAccountRetry = Date.distantPast
    @ObservationIgnored private var nearbyTrustWork: Task<Void, Never>?
    @ObservationIgnored private var nearbyTrustRetry: [String: Date] = [:]
    @ObservationIgnored private var accountObserver: NSObjectProtocol?
    @ObservationIgnored private var accountGeneration = 0
    @ObservationIgnored private var applying: Task<Void, Never>?
    @ObservationIgnored private var subscriptionWork: Task<Void, Never>?
    @ObservationIgnored private var alertSubscriptionChecked: Date?
    @ObservationIgnored private var sending: Set<String> = []
    @ObservationIgnored private var commandAnsweredAt: [String: Date] = [:]
    /// The Macs Siri and Spotlight last offered by name.
    @ObservationIgnored private var shortcutMacs: [Mac] = []
    @ObservationIgnored private var alertStates: [String: RemoteAlertState] =
        UserDefaults.standard.data(forKey: "remoteAlertStates").flatMap {
            try? RemoteWire.decode([String: RemoteAlertState].self, from: $0)
        } ?? [:]
    @ObservationIgnored private var silenceStates: [String: RemoteSilenceState] =
        UserDefaults.standard.data(forKey: "remoteSilenceStates").flatMap {
            try? RemoteWire.decode([String: RemoteSilenceState].self, from: $0)
        } ?? [:]

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
        nearby.onStatus = { [weak self] id, status in
            Task { @MainActor in
                guard let self, !self.isSample, self.nearbyTrust[id]?.discoveryID == status.nearbyID else { return }
                self.checking = false
                await self.apply(.init(statuses: [id: status], isComplete: false))
            }
        }
        if !isSample {
            accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.accountChanged() }
            }
            updateNearbyTrust()
        }
    }

    /// A local store with an already available snapshot; used for deterministic
    /// reconciliation checks without registering bridges or contacting iCloud.
    init(initialReadings: [String: Reading]) {
        readings = initialReadings
        macID = nil
        selectedID = nil
        isSample = false
    }

    func setForeground(_ active: Bool) {
        guard !isSample else { return }
        nearby.setForeground(active)
        if active { updateNearbyTrust() }
    }

    private func accountChanged() async {
        accountGeneration += 1
        nearbyTrustWork?.cancel()
        subscriptionWork?.cancel()
        nearby.stop()
        nearbyTrust = [:]
        nearbyAccountID = nil
        nearbyAccountRetry = .distantPast
        nearbyTrustRetry = [:]
        try? NearbyKeychain.remove(.phone)
        await cloud.accountDidChange()
        await applying?.value
        Notifications.cancelAll()
        UserDefaults.standard.set(false, forKey: Notifications.pushedKey)
        readings = [:]
        outdated = []
        alertStates = [:]
        silenceStates = [:]
        checking = true
        alertSubscriptionChecked = nil
        save()
        WidgetBridge.syncActivities([], confirmed: true)
        await WidgetBridge.settle()
    }

    private func updateNearbyTrust() {
        guard !isSample, nearbyTrustWork == nil, nearbyAccountRetry <= .now else { return }
        for (id, credential) in nearbyTrust where readings[id]?.status?.nearbyID != credential.discoveryID {
            nearbyTrust[id] = nil
            try? NearbyKeychain.remove(.phone, macID: id)
        }
        nearby.configure(Array(nearbyTrust.values))
        guard nearbyAccountID == nil || readings.contains(where: { id, reading in
            reading.status?.nearbyProtocol == 1 && reading.status?.nearbyID != nil &&
            nearbyTrust[id] == nil && (nearbyTrustRetry[id].map({ $0 <= .now }) ?? true)
        }) else { return }
        let generation = accountGeneration
        nearbyTrustWork = Task { [weak self] in
            guard let self else { return }
            defer { self.nearbyTrustWork = nil }
            if self.nearbyAccountID == nil {
                do {
                    let accountID = try await self.cloud.accountIdentity()
                    guard !Task.isCancelled, generation == self.accountGeneration, !self.isSample else { return }
                    self.nearbyAccountID = accountID
                    for (id, reading) in self.readings {
                        if let credential = try? NearbyKeychain.load(.phone, macID: id, accountID: accountID),
                           credential.discoveryID == reading.status?.nearbyID { self.nearbyTrust[id] = credential }
                    }
                    self.nearby.configure(Array(self.nearbyTrust.values))
                } catch {
                    if generation == self.accountGeneration { self.nearbyAccountRetry = .now.addingTimeInterval(60) }
                    return
                }
            }
            guard let accountID = self.nearbyAccountID else { return }
            let wanted = self.readings.compactMap { id, reading -> (String, String)? in
                guard reading.status?.nearbyProtocol == 1, let keyID = reading.status?.nearbyID,
                      self.nearbyTrust[id] == nil, self.nearbyTrustRetry[id].map({ $0 <= .now }) ?? true else { return nil }
                return (id, keyID)
            }
            for (id, keyID) in wanted {
                guard !Task.isCancelled, self.accountGeneration == generation, !self.isSample else { return }
                self.nearbyTrustRetry[id] = .now.addingTimeInterval(60)
                do {
                    guard let credential = try await self.cloud.nearbyCredential(macID: id, discoveryID: keyID),
                          self.accountGeneration == generation, self.readings[id]?.status?.nearbyID == keyID else { continue }
                    try NearbyKeychain.save(credential, owner: .phone, accountID: accountID)
                    self.nearbyTrust[id] = credential
                    self.nearby.configure(Array(self.nearbyTrust.values))
                } catch {}
            }
        }
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
        nearbyTrustWork?.cancel()
        nearby.stop()
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

    /// iOS ends a background wake after about 30 seconds without warning, and
    /// the widgets, Live Activity and alerts still need time after the read.
    static let backgroundRead: Duration = .seconds(20)

    /// Reads every Mac and reports the actual result to iOS background callers.
    @discardableResult
    func refreshAll(until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async -> UIBackgroundFetchResult {
        guard !Task.isCancelled, .now < deadline else { return .failed }
        // A push during a refresh may carry a newer change, and its handler
        // must not complete before that change is read.
        while refreshing {
            guard .now < deadline else { return .failed }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return .failed }
        }
        if isSample { return .noData }
        refreshing = true
        defer { refreshing = false }
        let generation = accountGeneration
        let startingReadings = readings
        let snapshot: RemoteCloud.Snapshot
        waitingForUpdate = false
        let slow = Task { [weak self] in
            try? await Task.sleep(for: Self.slowRead)
            guard !Task.isCancelled else { return }
            self?.waitingForUpdate = true
        }
        defer { slow.cancel(); waitingForUpdate = false }
        do {
            snapshot = try await cloud.fetch(knownMacIDs: Array(readings.keys), until: deadline)
            guard generation == accountGeneration else { return .failed }
            slow.cancel()
            problem = nil
        } catch is CancellationError {
            interruptSilenceConfirmation()
            return .failed
        } catch {
            guard !isSample, generation == accountGeneration else { return .noData }
            interruptSilenceConfirmation()
            if let selected, nearby.hasFreshConnection(to: selected.id) {
                await applying?.value
                problem = nil
                return startingReadings == readings ? .noData : .newData
            }
            problem = Self.describe(error)
            return .failed
        }
        // One that ended after the sample replaced the Macs says nothing about them.
        guard !isSample else { return .noData }
        checking = false
        let subscriptionDue = alertSubscriptionChecked.map { -$0.timeIntervalSinceNow > 120 } ?? true
        let previousReadings = readings
        let previousOutdated = outdated
        await apply(snapshot)
        updateNearbyTrust()
        // Notification housekeeping is independent of readings and commands.
        // Until confirmed, this phone retains the existing local-alert fallback.
        if subscriptionDue, subscriptionWork == nil {
            subscriptionWork = Task { [weak self] in
                await self?.syncAlertSubscription()
                self?.subscriptionWork = nil
            }
        }
        return readings == previousReadings && outdated == previousOutdated ? .noData : .newData
    }

    func apply(_ snapshot: RemoteCloud.Snapshot) async {
        let previous = applying
        let generation = accountGeneration
        let next = Task { [weak self] in
            await previous?.value
            guard let self, !self.isSample, generation == self.accountGeneration else { return }
            await self.applyNow(snapshot)
        }
        applying = next
        await next.value
        if applying == next { applying = nil }
    }

    private func applyNow(_ snapshot: RemoteCloud.Snapshot) async {
        var alerts: [(Mac, [RemoteAlert])] = []
        // Also a Mac never read before, so setup can say why it does not appear.
        if snapshot.isComplete { outdated = snapshot.unreadable }
        for (id, status) in snapshot.statuses {
            // A direct command answer may have arrived while discovery ran.
            if let current = readings[id]?.status, !status.isAtLeastAsRecent(as: current) { continue }
            let previous: RemoteStatus?? = readings[id].map { $0.reachable ? $0.status : nil }
            let fresh = status.isFresh()
            let reading = Reading(status: status, reachable: fresh)
            readings[id] = reading
            let mac = Mac(id: id, name: status.machineName)
            let pushed = UserDefaults.standard.bool(forKey: Notifications.pushedKey)
            var state = alertStates[id] ?? RemoteAlertState()
            var macAlerts = state.filter(Notifications.latchCharge(
                // A Mac that said it is going to sleep is not silent.
                RemoteAlert.alerts(from: previous, to: fresh || status.sleptAt != nil ? status : nil,
                                   chargeTarget: Notifications.chargeTarget),
                macID: id, status: fresh ? status : nil), status: status)
            alertStates[id] = state
            macAlerts = macAlerts.filter { !pushed || !RemoteAlert.pushedKinds.contains($0.kind) }
            var silence = silenceStates[id] ?? RemoteSilenceState()
            if Notifications.isEnabled {
                if silence.observe(status) { macAlerts.append(.unreachable) }
            } else {
                silence.interrupt()
            }
            silenceStates[id] = silence
            alerts.append((mac, macAlerts))
            await Notifications.syncReminders(for: mac, reading: reading)
        }
        // Its last readable status stays, but no longer as live.
        for id in snapshot.unreadable where readings[id] != nil {
            readings[id]?.reachable = false
            silenceStates[id]?.interrupt()
        }
        // A Mac that stopped sharing is gone, not silent.
        for id in readings.keys where snapshot.isComplete && snapshot.statuses[id] == nil && !snapshot.unreadable.contains(id) {
            if commandAnsweredAt[id].map({ $0 > snapshot.requestedAt }) == true { continue }
            if nearby.hasFreshConnection(to: id) { continue }
            readings[id] = nil
            alertStates[id] = nil
            silenceStates[id] = nil
            await Notifications.syncReminders(for: Mac(id: id, name: ""), reading: nil)
        }
        save()
        await WidgetBridge.settle()
        LocalPhoneMonitor.shared.learnHotspotName(from: readings)
        // Awaited so a background task does not complete before the alerts are added.
        await Notifications.deliver(alerts)
    }

    /// Keeps iCloud's alert subscription in step with the Notifications
    /// switch. The subscription belongs to the account, so it is checked on
    /// the server rather than remembered: another phone, or iCloud recreating
    /// the zone, can remove it. Until it is confirmed, this phone raises every
    /// alert itself. Only turning the switch off removes it; a routine check
    /// never does, since another iPhone on the account may still want it.
    func syncAlertSubscription(removing: Bool = false) async {
        if !Notifications.isEnabled { Notifications.cancelAll() }
        // Sample controls must not contact or change the real iCloud account.
        guard !isSample else { return }
        let generation = accountGeneration
        alertSubscriptionChecked = .now
        let wanted = Notifications.isEnabled
        let defaults = UserDefaults.standard
        // Kept until iCloud confirms, so an offline switch-off is retried.
        if removing { defaults.set(true, forKey: Self.removalPendingKey) }
        do {
            if wanted {
                defaults.set(false, forKey: Self.removalPendingKey)
                let subscribed = try await cloud.hasAlertSubscription()
                guard generation == accountGeneration else { return }
                if !subscribed {
                    try await cloud.subscribeToAlerts()
                    guard generation == accountGeneration else { return }
                    // Confirmed by the next refresh, which then leaves the Mac's alerts to iCloud.
                    alertSubscriptionChecked = nil
                }
                // What the Mac posted while it was missing never reached this iPhone.
                UserDefaults.standard.set(subscribed, forKey: Notifications.pushedKey)
            } else {
                if defaults.bool(forKey: Self.removalPendingKey) {
                    try await cloud.unsubscribeFromAlerts()
                    guard generation == accountGeneration else { return }
                    defaults.set(false, forKey: Self.removalPendingKey)
                }
                UserDefaults.standard.set(false, forKey: Notifications.pushedKey)
            }
        } catch {
            guard generation == accountGeneration else { return }
            // A failed check does not establish that an accepted subscription
            // disappeared. Switching to local alerts here can duplicate pushes.
            if let error = error as? CKError, [.zoneNotFound, .userDeletedZone].contains(error.code) {
                defaults.set(false, forKey: Notifications.pushedKey)
            }
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
            try await cloud.delete([mac.id, RemoteCloud.commandRecordName(for: mac.id)])
        } catch {
            return Self.describe(error)
        }
        readings[mac.id] = nil
        nearbyTrust[mac.id] = nil
        try? NearbyKeychain.remove(.phone, macID: mac.id)
        nearby.configure(Array(nearbyTrust.values))
        await Notifications.syncReminders(for: mac, reading: nil)
        alertStates[mac.id] = nil
        silenceStates[mac.id] = nil
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
        request.deviceName = LocalPhoneMonitor.shared.commandName
        // A second change to the same Mac is refused, not queued indefinitely.
        let locks = request.operation != .inspect
        if locks { pending[mac.id] = request.operation }
        defer { if locks, pending[mac.id] == request.operation { pending[mac.id] = nil } }
        sending.insert(mac.id)
        defer { sending.remove(mac.id) }
        request.sentAt = .now
        let generation = accountGeneration
        if isSample, var status = readings[mac.id]?.status {
            try? await Task.sleep(for: .seconds(request.operation == .inspect ? 2 : 0.6))
            guard isSample else { return nil }
            DemoData.apply(request, to: &status)
            readings[mac.id] = .init(status: status, reachable: true)
            publishSelected()
            return nil
        }
        do {
            let status = try await RemoteHandoff.execute(request, routes: nearby.routes(to: mac.id), to: mac.id, cloud: cloud)
            guard generation == accountGeneration else { return String(localized: "The Apple Account changed. Check the Mac before trying again.") }
            commandAnsweredAt[mac.id] = .now
            if readings[mac.id]?.status.map({ status.isAtLeastAsRecent(as: $0) }) ?? true {
                let reading = Reading(status: status, reachable: status.isFresh())
                readings[mac.id] = reading
                var silence = silenceStates[mac.id] ?? RemoteSilenceState()
                _ = silence.observe(status)
                silenceStates[mac.id] = silence
                await Notifications.syncReminders(for: mac, reading: reading)
                save()
            }
            return status.lastCommand?.failure.map(Self.message)
        } catch is CancellationError {
            return String(localized: "Cancelled.")
        } catch is RemoteDeadline.Failure {
            return String(localized: "The change wasn't confirmed. Check your Mac's status before trying again.", table: "RemoteSync")
        } catch {
            return Self.describe(error)
        }
    }

    private func save() {
        UserDefaults.standard.set(try? RemoteWire.encode(readings), forKey: "readings")
        saveAlertStates()
        publishSelected()
    }

    private func saveAlertStates() {
        UserDefaults.standard.set(try? RemoteWire.encode(alertStates), forKey: "remoteAlertStates")
        UserDefaults.standard.set(try? RemoteWire.encode(silenceStates), forKey: "remoteSilenceStates")
    }

    private func interruptSilenceConfirmation() {
        for id in silenceStates.keys { silenceStates[id]?.interrupt() }
        saveAlertStates()
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
