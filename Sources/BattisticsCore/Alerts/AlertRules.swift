import Foundation

public enum BatteryAlert: Sendable, Equatable {
    case lowBattery(percent: Int)
    case significantDrop(percent: Int)
    case chargeLimitReached(percent: Int)
    case fullyCharged
    case highTemperature(celsius: Double)
    case onBatteryDuration(hours: Double)
    case healthDropped(from: Double, to: Double)
}

public struct AlertConfig: Sendable, Equatable {
    public var lowBatteryEnabled: Bool
    public var lowBatteryThreshold: Int
    public var significantDropEnabled: Bool
    public var significantDropStep: Int
    public var chargeLimitEnabled: Bool
    public var chargeLimitThreshold: Int
    public var fullChargeEnabled: Bool
    public var highTemperatureEnabled: Bool
    public var highTemperatureThresholdC: Double
    public var onBatteryDurationEnabled: Bool
    public var onBatteryDurationHours: Double

    public init(
        lowBatteryEnabled: Bool = true,
        lowBatteryThreshold: Int = 20,
        significantDropEnabled: Bool = true,
        significantDropStep: Int = 5,
        chargeLimitEnabled: Bool = false,
        chargeLimitThreshold: Int = 80,
        fullChargeEnabled: Bool = true,
        highTemperatureEnabled: Bool = true,
        highTemperatureThresholdC: Double = 40,
        onBatteryDurationEnabled: Bool = false,
        onBatteryDurationHours: Double = 3
    ) {
        self.lowBatteryEnabled = lowBatteryEnabled
        self.lowBatteryThreshold = lowBatteryThreshold
        self.significantDropEnabled = significantDropEnabled
        self.significantDropStep = significantDropStep
        self.chargeLimitEnabled = chargeLimitEnabled
        self.chargeLimitThreshold = chargeLimitThreshold
        self.fullChargeEnabled = fullChargeEnabled
        self.highTemperatureEnabled = highTemperatureEnabled
        self.highTemperatureThresholdC = highTemperatureThresholdC
        self.onBatteryDurationEnabled = onBatteryDurationEnabled
        self.onBatteryDurationHours = onBatteryDurationHours
    }
}

/// Mutable evaluation state carried between snapshots so alerts fire once
/// per crossing instead of repeating on every sample.
public struct AlertState: Sendable, Equatable {
    public var lowBatteryFired = false
    public var lastDropNotifiedPercent: Int?
    public var chargeLimitFired = false
    public var fullChargeFired = false
    public var highTemperatureFired = false
    public var unpluggedAt: Date?
    public var onBatteryDurationFired = false

    public init() {}
}

/// Pure alert evaluation: (snapshot, config, state) in, alerts out.
/// The app layer owns delivery; this stays unit-testable.
public enum AlertRules {
    public static func evaluate(
        snapshot: BatterySnapshot,
        config: AlertConfig,
        state: inout AlertState,
        now: Date = Date()
    ) -> [BatteryAlert] {
        var alerts: [BatteryAlert] = []

        // Track the unplug moment for the duration reminder.
        if snapshot.externalConnected {
            state.unpluggedAt = nil
            state.onBatteryDurationFired = false
        } else if state.unpluggedAt == nil {
            state.unpluggedAt = now
        }

        if config.lowBatteryEnabled, !snapshot.externalConnected {
            if snapshot.percent <= config.lowBatteryThreshold {
                if !state.lowBatteryFired {
                    state.lowBatteryFired = true
                    state.lastDropNotifiedPercent = snapshot.percent
                    alerts.append(.lowBattery(percent: snapshot.percent))
                } else if config.significantDropEnabled,
                    let last = state.lastDropNotifiedPercent,
                    snapshot.percent <= last - config.significantDropStep {
                    state.lastDropNotifiedPercent = snapshot.percent
                    alerts.append(.significantDrop(percent: snapshot.percent))
                }
            } else {
                state.lowBatteryFired = false
                state.lastDropNotifiedPercent = nil
            }
        } else if snapshot.externalConnected {
            state.lowBatteryFired = false
            state.lastDropNotifiedPercent = nil
        }

        if config.chargeLimitEnabled, snapshot.externalConnected {
            if snapshot.percent >= config.chargeLimitThreshold, snapshot.percent < 100 {
                if !state.chargeLimitFired {
                    state.chargeLimitFired = true
                    alerts.append(.chargeLimitReached(percent: snapshot.percent))
                }
            }
        } else {
            state.chargeLimitFired = false
        }

        if config.fullChargeEnabled, snapshot.externalConnected,
            snapshot.percent >= 100 || snapshot.fullyCharged {
            if !state.fullChargeFired {
                state.fullChargeFired = true
                alerts.append(.fullyCharged)
            }
        } else if !snapshot.externalConnected {
            state.fullChargeFired = false
        }

        if config.highTemperatureEnabled, let temperature = snapshot.temperatureC {
            if temperature >= config.highTemperatureThresholdC {
                if !state.highTemperatureFired {
                    state.highTemperatureFired = true
                    alerts.append(.highTemperature(celsius: temperature))
                }
            } else if temperature < config.highTemperatureThresholdC - 2 {
                state.highTemperatureFired = false
            }
        }

        if config.onBatteryDurationEnabled, !snapshot.externalConnected,
            let unpluggedAt = state.unpluggedAt {
            let hours = now.timeIntervalSince(unpluggedAt) / 3600
            if hours >= config.onBatteryDurationHours, !state.onBatteryDurationFired {
                state.onBatteryDurationFired = true
                alerts.append(.onBatteryDuration(hours: hours))
            }
        }

        return alerts
    }

    /// Health drop detection runs at the daily snapshot cadence, not per
    /// power event, so it lives outside `evaluate`.
    /// Real degradation is a few points a year, while the daily reading
    /// swings that much on its own. So the comparison is against the median
    /// of the recorded history, not yesterday, and the margin is wide enough
    /// to clear the observed swing. A health notification should be rare and
    /// mean something; day-over-day comparison made it noise.
    public static let healthDeclineMargin = 3.0

    public static func healthDropAlert(baseline: [Double], current: Double, enabled: Bool) -> BatteryAlert? {
        guard enabled, let rawBaseline = BatteryHealth.median(baseline) else { return nil }
        let from = BatteryHealth.display(rawBaseline)
        let to = BatteryHealth.display(current)
        guard to < from - healthDeclineMargin else { return nil }
        return .healthDropped(from: from, to: to)
    }
}
