import AppKit
import BattisticsCore
import Foundation
import Observation

/// Single source of truth for UI state. Consumes core event streams and
/// owns the recording pipeline. Kept deliberately thin: all logic that can
/// be pure lives in BattisticsCore where it is unit-tested.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: BatterySnapshot?
    private(set) var lastUnplugDate: Date?
    private(set) var sparkline: [SeriesPoint] = []

    let history: HistoryStore

    @ObservationIgnored private let monitor = PowerSourceMonitor()
    @ObservationIgnored private let alertDispatcher = AlertDispatcher()
    @ObservationIgnored private var alertState = AlertState()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var powerSamplingTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// Baseline for transition detection, updated only when a transition is
    /// handled so no read path can mask another's changes.
    @ObservationIgnored private var lastTransitionSnapshot: BatterySnapshot?

    init(historyDirectory: URL? = nil) {
        Prefs.registerDefaults()
        let directory =
            historyDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Battistics", isDirectory: true)
        history = HistoryStore(directory: directory)

        refreshSensors()
        startMonitoring()
        restartPowerSampling()
        observeWake()
        observeDefaults()
        // Deferred: NSApplication does not exist yet during App.init.
        Task { @MainActor [weak self] in
            self?.applyActivationPolicy()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.history.runRetention()
            if self.snapshot?.externalConnected == false,
                let storedUnplug = await self.history.lastUnplugDate() {
                // Restore the real unplug moment across relaunches, both for
                // the UI and for the on-battery duration alert.
                self.lastUnplugDate = storedUnplug
                self.alertState.unpluggedAt = storedUnplug
            }
        }
    }

    // MARK: - Live data

    /// Re-reads the battery and funnels the result through the single
    /// ingestion point. Safe to call from any path, any frequency.
    func refreshSensors() {
        guard let current = BatteryReader.read() else {
            snapshot = nil
            return
        }
        ingest(current)
    }

    /// Every snapshot from every source passes through here, so state
    /// transitions are recorded and alerted no matter which path (power
    /// event, UI poll, background sampler) observed them first.
    private func ingest(_ current: BatterySnapshot) {
        let previous = lastTransitionSnapshot
        snapshot = current
        evaluateAlerts(for: current)

        let changed =
            previous == nil
            || previous?.percent != current.percent
            || previous?.externalConnected != current.externalConnected
            || previous?.isCharging != current.isCharging
        guard changed else { return }
        lastTransitionSnapshot = current

        trackUnplug(previous: previous, current: current)
        let sample = ChargeSample(
            date: current.timestamp,
            percent: current.percent,
            externalConnected: current.externalConnected,
            isCharging: current.isCharging
        )
        Task { [weak self] in
            await self?.history.recordChargeSample(sample)
        }
        maybeRecordDailyHealth(current)
    }

    func loadSparkline() async {
        let now = Date()
        sparkline = await history.chargeSeries(
            from: now.addingTimeInterval(-24 * 3600), to: now, bucketSeconds: 600)
    }

    private func startMonitoring() {
        let events = monitor.start()
        monitorTask = Task { [weak self] in
            for await _ in events {
                self?.refreshSensors()
            }
        }
    }

    private func trackUnplug(previous: BatterySnapshot?, current: BatterySnapshot) {
        if current.externalConnected {
            lastUnplugDate = nil
        } else if previous?.externalConnected != false {
            lastUnplugDate = Date()
        }
    }

    // MARK: - Background power sampling (single coalesced tick, toggleable)

    func restartPowerSampling() {
        powerSamplingTask?.cancel()
        powerSamplingTask = nil
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.powerSamplingEnabled) else { return }
        let interval = max(defaults.double(forKey: Prefs.powerSamplingInterval), 30)
        powerSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .seconds(interval), tolerance: .seconds(interval * 0.25))
                guard !Task.isCancelled else { break }
                await self?.recordPowerSample()
            }
        }
    }

    private func recordPowerSample() async {
        guard let current = BatteryReader.read() else { return }
        ingest(current)
        guard current.batteryInstalled, let watts = current.watts else { return }
        await history.recordPowerSample(
            date: current.timestamp,
            watts: abs(watts),
            volts: current.voltageMV.map { Double($0) / 1000 },
            amps: current.amperageMA.map { Double($0) / 1000 },
            temperatureC: current.temperatureC
        )
    }

    // MARK: - Alerts and health snapshots

    private func evaluateAlerts(for snapshot: BatterySnapshot) {
        let alerts = AlertRules.evaluate(
            snapshot: snapshot, config: Prefs.alertConfig(), state: &alertState)
        for alert in alerts {
            alertDispatcher.deliver(alert)
        }
    }

    private func maybeRecordDailyHealth(_ snapshot: BatterySnapshot) {
        guard snapshot.batteryInstalled, snapshot.designCapacity > 0 else { return }
        Task { [weak self] in
            guard let self else { return }
            guard !(await self.history.hasHealthSnapshot(forDay: snapshot.timestamp)) else { return }
            // Piggyback retention on the daily snapshot so long-running
            // sessions keep compacting without a relaunch.
            await self.history.runRetention()
            let previous = await self.history.recordHealthSnapshot(
                date: snapshot.timestamp,
                healthPercent: snapshot.healthPercent,
                rawMaxCapacity: snapshot.rawMaxCapacity,
                nominalCapacity: snapshot.nominalCapacity,
                designCapacity: snapshot.designCapacity,
                cycleCount: snapshot.cycleCount
            )
            let enabled = UserDefaults.standard.bool(forKey: Prefs.alertHealthDropEnabled)
            if let alert = AlertRules.healthDropAlert(
                previous: previous, current: snapshot.healthPercent, enabled: enabled) {
                self.alertDispatcher.deliver(alert)
            }
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSensors()
            }
        }
    }

    /// Keeps the app reachable: if both the menu bar icon and the Dock icon
    /// end up disabled (e.g. the user Cmd-drags the icon off the menu bar),
    /// force the Dock icon back on.
    private func observeDefaults() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Deferred out of the notification callback: defaults change
            // notifications can fire inside NSApplication's own init.
            Task { @MainActor in
                let defaults = UserDefaults.standard
                if !defaults.bool(forKey: Prefs.showMenuBarIcon),
                    !defaults.bool(forKey: Prefs.showDockIcon) {
                    defaults.set(true, forKey: Prefs.showDockIcon)
                }
                self?.applyActivationPolicy()
            }
        }
    }

    // MARK: - Dock icon policy

    /// The Dock icon strictly follows the preference. Windows open fine
    /// under the accessory policy, they just do not appear in Cmd-Tab.
    func applyActivationPolicy() {
        // Never force-create the application object here: this can run
        // while NSApplication is still initializing (UserDefaults writes
        // during its init post notifications), and touching
        // NSApplication.shared reentrantly asserts. Once the app exists,
        // NSApp is non-nil and this becomes effective.
        guard let app = NSApp else { return }
        let showDock = UserDefaults.standard.bool(forKey: Prefs.showDockIcon)
        let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if app.activationPolicy() != policy {
            app.setActivationPolicy(policy)
        }
    }
}
