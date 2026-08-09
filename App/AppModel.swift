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
    @ObservationIgnored private var dashboardWindowCount = 0

    init(historyDirectory: URL? = nil) {
        Prefs.registerDefaults()
        let directory =
            historyDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Battistics", isDirectory: true)
        history = HistoryStore(directory: directory)

        handlePowerEvent()
        startMonitoring()
        restartPowerSampling()
        observeWake()
        applyActivationPolicy()

        Task { [weak self] in
            guard let self else { return }
            await self.history.runRetention()
            if self.snapshot?.externalConnected == false,
                let storedUnplug = await self.history.lastUnplugDate() {
                self.lastUnplugDate = storedUnplug
            }
        }
    }

    // MARK: - Live data

    /// Re-reads sensors without recording. Driven by visible UI only.
    func refreshSensors() {
        snapshot = BatteryReader.read()
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
                self?.handlePowerEvent()
            }
        }
    }

    private func handlePowerEvent() {
        let previous = snapshot
        guard let current = BatteryReader.read() else {
            snapshot = nil
            return
        }
        snapshot = current

        let changed =
            previous == nil
            || previous?.percent != current.percent
            || previous?.externalConnected != current.externalConnected
            || previous?.isCharging != current.isCharging
        guard changed else { return }

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
        evaluateAlerts(for: current)
        maybeRecordDailyHealth(current)
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
        snapshot = current
        evaluateAlerts(for: current)
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
                self?.handlePowerEvent()
            }
        }
    }

    // MARK: - Dock icon policy

    func dashboardDidAppear() {
        dashboardWindowCount += 1
        applyActivationPolicy()
    }

    func dashboardDidDisappear() {
        dashboardWindowCount = max(0, dashboardWindowCount - 1)
        applyActivationPolicy()
    }

    func applyActivationPolicy() {
        let showDock = UserDefaults.standard.bool(forKey: Prefs.showDockIcon)
        let policy: NSApplication.ActivationPolicy =
            (showDock || dashboardWindowCount > 0) ? .regular : .accessory
        // NSApplication.shared, not NSApp: this can run from AppModel.init
        // before the NSApp global is populated.
        let app = NSApplication.shared
        if app.activationPolicy() != policy {
            app.setActivationPolicy(policy)
        }
    }
}
