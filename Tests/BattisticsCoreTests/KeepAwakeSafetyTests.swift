import Foundation
import Testing
@testable import BattisticsCore

@Suite("Keep Awake session protection")
struct KeepAwakeSafetyTests {
    private func battery(_ percent: Int, ac: Bool = false, installed: Bool = true) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(), batteryInstalled: installed, percent: percent,
            rawCurrentCapacity: 1000, rawMaxCapacity: 6000, nominalCapacity: nil,
            designCapacity: 6000, cycleCount: 10, designCycleCount: nil,
            temperatureC: 30, voltageMV: nil, amperageMA: nil,
            isCharging: false, externalConnected: ac, fullyCharged: false,
            avgTimeToEmptyMin: nil, avgTimeToFullMin: nil, systemTimeRemainingMin: nil,
            systemHealthStatus: nil, serialNumber: nil, deviceName: nil,
            manufactureDate: nil, adapter: nil)
    }

    @Test func stoppingIsOptInEvenAtOnePercentAndHighThermalPressure() {
        var policy = KeepAwakeSafetyPolicy()
        let events = policy.evaluate(snapshot: battery(1), thermalPressure: true, configuration: .init())
        #expect(events == [.batteryWarning(percent: 1, stopAt: nil), .thermalWarning])
        #expect(!events.contains { $0.endsSession })
    }

    @Test func warningPrecedesStopAndDoesNotRepeatOnEveryReading() {
        var policy = KeepAwakeSafetyPolicy()
        let configuration = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true)
        #expect(policy.evaluate(snapshot: battery(21), thermalPressure: false, configuration: configuration).isEmpty)
        #expect(policy.evaluate(snapshot: battery(20), thermalPressure: false, configuration: configuration)
                == [.batteryWarning(percent: 20, stopAt: 10)])
        #expect(policy.evaluate(snapshot: battery(19), thermalPressure: false, configuration: configuration).isEmpty)
        #expect(policy.evaluate(snapshot: battery(10), thermalPressure: false, configuration: configuration)
                == [.batteryStop(percent: 10)])
    }

    @Test func skippedWarningLevelStillStopsAndStartPreflightMatches() {
        var policy = KeepAwakeSafetyPolicy()
        let configuration = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true)
        #expect(policy.evaluate(snapshot: battery(60), thermalPressure: false, configuration: configuration).isEmpty)
        #expect(policy.evaluate(snapshot: battery(3), thermalPressure: false, configuration: configuration)
                == [.batteryStop(percent: 3)])
        #expect(KeepAwakeSafetyPolicy.stopReason(snapshot: battery(3), thermalPressure: false,
                                               configuration: configuration) == .batteryStop(percent: 3))
    }

    @Test func adapterExemptsBatteryEvenWhenNotChargingAndUnplugReevaluates() {
        var policy = KeepAwakeSafetyPolicy()
        let configuration = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true)
        #expect(policy.evaluate(snapshot: battery(1, ac: true), thermalPressure: false, configuration: configuration).isEmpty)
        #expect(policy.evaluate(snapshot: battery(1), thermalPressure: false, configuration: configuration)
                == [.batteryStop(percent: 1)])
    }

    @Test func noBatteryMissingDataAndInvalidPercentNeverActLikeAnEmptyBattery() {
        let configuration = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true)
        for snapshot in [nil, battery(0, installed: false), battery(-1), battery(101)] {
            var policy = KeepAwakeSafetyPolicy()
            #expect(policy.evaluate(snapshot: snapshot, thermalPressure: false, configuration: configuration).isEmpty)
        }
    }

    @Test func rechargeRearmsWarningAndSmallGaugeJitterDoesNot() {
        var policy = KeepAwakeSafetyPolicy()
        let configuration = KeepAwakeSafetyPolicy.Configuration()
        _ = policy.evaluate(snapshot: battery(20), thermalPressure: false, configuration: configuration)
        _ = policy.evaluate(snapshot: battery(21), thermalPressure: false, configuration: configuration)
        #expect(policy.evaluate(snapshot: battery(20), thermalPressure: false, configuration: configuration).isEmpty)
        _ = policy.evaluate(snapshot: battery(20, ac: true), thermalPressure: false, configuration: configuration)
        #expect(policy.evaluate(snapshot: battery(20), thermalPressure: false, configuration: configuration)
                == [.batteryWarning(percent: 20, stopAt: nil)])
    }

    @Test func warningCanBeDisabledWithoutDisablingTheStop() {
        var policy = KeepAwakeSafetyPolicy()
        let configuration = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true, warnOnLowBattery: false)
        #expect(policy.evaluate(snapshot: battery(15), thermalPressure: false, configuration: configuration).isEmpty)
        #expect(policy.evaluate(snapshot: battery(9), thermalPressure: false, configuration: configuration)
                == [.batteryStop(percent: 9)])
    }

    @Test func configChangeDuringSessionTakesEffectImmediately() {
        var policy = KeepAwakeSafetyPolicy()
        _ = policy.evaluate(snapshot: battery(8), thermalPressure: false, configuration: .init())
        #expect(policy.evaluate(snapshot: battery(8), thermalPressure: false,
                               configuration: .init(stopOnLowBattery: true)) == [.batteryStop(percent: 8)])
    }

    @Test func thermalWarningRearmsAfterRecoveryAndOptionalStopWorksOnAC() {
        var policy = KeepAwakeSafetyPolicy()
        #expect(policy.evaluate(snapshot: battery(100, ac: true), thermalPressure: true, configuration: .init()) == [.thermalWarning])
        #expect(policy.evaluate(snapshot: nil, thermalPressure: true, configuration: .init()).isEmpty)
        #expect(policy.evaluate(snapshot: nil, thermalPressure: false, configuration: .init()).isEmpty)
        #expect(policy.evaluate(snapshot: nil, thermalPressure: true, configuration: .init()) == [.thermalWarning])
        #expect(policy.evaluate(snapshot: battery(100, ac: true), thermalPressure: true,
                               configuration: .init(stopOnThermalPressure: true)) == [.thermalStop])
    }

    @Test func corruptThresholdsAreBoundedAndWarningRemainsAboveStop() {
        let low = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true, stopPercent: -100, warningPercent: -100)
        let high = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true, stopPercent: 900, warningPercent: 900)
        let reversed = KeepAwakeSafetyPolicy.Configuration(stopOnLowBattery: true, stopPercent: 40, warningPercent: 10)
        #expect(low.effectiveStopPercent == 5)
        #expect(low.effectiveWarningPercent == 10)
        #expect(high.effectiveStopPercent == 50)
        #expect(high.effectiveWarningPercent == 80)
        #expect(reversed.effectiveWarningPercent == 45)
    }
}
