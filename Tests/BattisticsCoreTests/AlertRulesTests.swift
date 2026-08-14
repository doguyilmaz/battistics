import Foundation
import Testing

@testable import BattisticsCore

@Suite("Alert rules")
struct AlertRulesTests {
    private func snapshot(
        percent: Int,
        external: Bool = false,
        charging: Bool = false,
        fullyCharged: Bool = false,
        temperatureC: Double? = 30
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(),
            batteryInstalled: true,
            percent: percent,
            rawCurrentCapacity: 4000,
            rawMaxCapacity: 5900,
            nominalCapacity: nil,
            designCapacity: 6075,
            cycleCount: 100,
            designCycleCount: 1000,
            temperatureC: temperatureC,
            voltageMV: 12000,
            amperageMA: -500,
            isCharging: charging,
            externalConnected: external,
            fullyCharged: fullyCharged,
            avgTimeToEmptyMin: nil,
            avgTimeToFullMin: nil,
            systemTimeRemainingMin: nil,
            systemHealthStatus: nil,
            serialNumber: nil,
            deviceName: nil,
            manufactureDate: nil,
            adapter: nil
        )
    }

    @Test func lowBatteryFiresOncePerCrossing() {
        var state = AlertState()
        let config = AlertConfig()

        var alerts = AlertRules.evaluate(snapshot: snapshot(percent: 20), config: config, state: &state)
        #expect(alerts == [.lowBattery(percent: 20)])

        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 19), config: config, state: &state)
        #expect(alerts.isEmpty)

        // Recharge above threshold resets the latch.
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 50, external: true, charging: true), config: config, state: &state)
        #expect(alerts.isEmpty)
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 20), config: config, state: &state)
        #expect(alerts == [.lowBattery(percent: 20)])
    }

    @Test func significantDropRemindsEveryStep() {
        var state = AlertState()
        let config = AlertConfig(significantDropStep: 5)

        _ = AlertRules.evaluate(snapshot: snapshot(percent: 20), config: config, state: &state)
        var alerts = AlertRules.evaluate(snapshot: snapshot(percent: 16), config: config, state: &state)
        #expect(alerts.isEmpty)
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 15), config: config, state: &state)
        #expect(alerts == [.significantDrop(percent: 15)])
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 10), config: config, state: &state)
        #expect(alerts == [.significantDrop(percent: 10)])
    }

    @Test func chargeLimitFiresOnlyWhilePluggedAndBelowFull() {
        var state = AlertState()
        let config = AlertConfig(chargeLimitEnabled: true, chargeLimitThreshold: 80)

        var alerts = AlertRules.evaluate(snapshot: snapshot(percent: 80, external: true, charging: true), config: config, state: &state)
        #expect(alerts == [.chargeLimitReached(percent: 80)])
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 85, external: true, charging: true), config: config, state: &state)
        #expect(alerts.isEmpty)

        // Unplugging resets the latch.
        _ = AlertRules.evaluate(snapshot: snapshot(percent: 70), config: config, state: &state)
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 81, external: true, charging: true), config: config, state: &state)
        #expect(alerts == [.chargeLimitReached(percent: 81)])
    }

    @Test func fullChargeFiresOnce() {
        var state = AlertState()
        let config = AlertConfig()

        var alerts = AlertRules.evaluate(
            snapshot: snapshot(percent: 100, external: true, fullyCharged: true), config: config, state: &state)
        #expect(alerts == [.fullyCharged])
        alerts = AlertRules.evaluate(
            snapshot: snapshot(percent: 100, external: true, fullyCharged: true), config: config, state: &state)
        #expect(alerts.isEmpty)
    }

    @Test func highTemperatureUsesHysteresis() {
        var state = AlertState()
        let config = AlertConfig(highTemperatureThresholdC: 40)

        var alerts = AlertRules.evaluate(snapshot: snapshot(percent: 50, temperatureC: 41), config: config, state: &state)
        #expect(alerts == [.highTemperature(celsius: 41)])
        // Still hot: no repeat. Slightly cooler but inside hysteresis band: no reset.
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 50, temperatureC: 39), config: config, state: &state)
        #expect(alerts.isEmpty)
        // Below band resets, next crossing fires again.
        _ = AlertRules.evaluate(snapshot: snapshot(percent: 50, temperatureC: 36), config: config, state: &state)
        alerts = AlertRules.evaluate(snapshot: snapshot(percent: 50, temperatureC: 42), config: config, state: &state)
        #expect(alerts == [.highTemperature(celsius: 42)])
    }

    @Test func onBatteryDurationFiresAfterConfiguredHours() {
        var state = AlertState()
        let config = AlertConfig(onBatteryDurationEnabled: true, onBatteryDurationHours: 3)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        var alerts = AlertRules.evaluate(snapshot: snapshot(percent: 90), config: config, state: &state, now: start)
        #expect(alerts.isEmpty)
        alerts = AlertRules.evaluate(
            snapshot: snapshot(percent: 70), config: config, state: &state, now: start.addingTimeInterval(2 * 3600))
        #expect(alerts.isEmpty)
        alerts = AlertRules.evaluate(
            snapshot: snapshot(percent: 60), config: config, state: &state, now: start.addingTimeInterval(3.1 * 3600))
        #expect(alerts.count == 1)
        if case .onBatteryDuration(let hours) = alerts[0] {
            #expect(hours > 3)
        } else {
            Issue.record("Expected onBatteryDuration, got \(alerts)")
        }
    }

    @Test func healthDropDetection() {
        #expect(
            AlertRules.healthDropAlert(baseline: [90, 90, 90], current: 85, enabled: true)
                == .healthDropped(from: 90, to: 85))
        #expect(AlertRules.healthDropAlert(baseline: [90, 90, 90], current: 89.8, enabled: true) == nil)
        #expect(AlertRules.healthDropAlert(baseline: [], current: 89, enabled: true) == nil)
        #expect(AlertRules.healthDropAlert(baseline: [90, 90, 90], current: 80, enabled: false) == nil)
    }

    @Test func healthDropStaysSilentWhileTheGaugeRelearnsAboveDesign() {
        // A new pack settles 104 -> 101 as the gauge relearns Qmax. Both
        // readings clamp to 100, so this is not a decline and must not alert.
        #expect(AlertRules.healthDropAlert(baseline: [104], current: 101, enabled: true) == nil)
        // Crossing below 100 reports the clamped figure, never a fictional 104.
        #expect(
            AlertRules.healthDropAlert(baseline: [102, 103, 102], current: 96, enabled: true)
                == .healthDropped(from: 100, to: 96))
    }

    @Test func healthDropIgnoresTheDailyGaugeSwing() {
        // Five real consecutive days off an M-series Mac. Day-over-day this
        // fired three spurious "health declined" notifications.
        let observed = [89.37, 87.97, 87.11, 86.12]
        #expect(AlertRules.healthDropAlert(baseline: observed, current: 89.73, enabled: true) == nil)
        // A low day inside the normal swing is still noise, not decline.
        #expect(AlertRules.healthDropAlert(baseline: observed, current: 85.5, enabled: true) == nil)
    }

    @Test func healthDropFiresOnADeclineBeyondTheSwing() {
        let observed = [89.37, 87.97, 87.11, 86.12]
        let alert = AlertRules.healthDropAlert(baseline: observed, current: 83.5, enabled: true)
        guard case .healthDropped(let from, let to) = alert else {
            Issue.record("Expected healthDropped, got \(String(describing: alert))")
            return
        }
        // Median of an even-length window is a computed mean, so compare
        // with a tolerance rather than for exact equality.
        #expect(abs(from - 87.54) < 0.001)
        #expect(to == 83.5)
    }
}
