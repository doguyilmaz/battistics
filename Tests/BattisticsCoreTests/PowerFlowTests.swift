import Foundation
import Testing

@testable import BattisticsCore

@Suite("Experimental power flow")
struct PowerFlowTests {
    private let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func props(
        input: Any? = 14_099, load: Any? = 14_099, battery: Any? = 0,
        charging: Any? = false, external: Any? = true, current: Any? = 0,
        updateTime: Any? = nil
    ) -> [String: Any] {
        var telemetry: [String: Any] = [:]
        telemetry["SystemPowerIn"] = input
        telemetry["SystemLoad"] = load
        telemetry["BatteryPower"] = battery
        var result: [String: Any] = ["PowerTelemetryData": telemetry]
        result["IsCharging"] = charging
        result["ExternalConnected"] = external
        result["Amperage"] = current
        result["UpdateTime"] = updateTime
        return result
    }

    @Test func optInIsRequiredAndExistingMeasurementsArePreserved() throws {
        let raw = props()
        let before = BatteryReader.snapshot(from: raw, iops: nil, now: readAt)
        let enabled = BatteryReader.snapshot(from: raw, iops: nil, now: readAt, includePowerFlow: true)
        #expect(before.powerFlow == nil)
        let flow = try #require(enabled.powerFlow)
        #expect(flow.inputWatts == 14.099)
        #expect(flow.systemLoadWatts == 14.099)
        #expect(flow.batteryPowerWatts == 0)
        #expect(flow.batteryDirection == .idle)
        #expect(flow.readAt == readAt)
        #expect(flow.source == "AppleSmartBattery.PowerTelemetryData")
        #expect(enabled.watts == before.watts)
        #expect(enabled.adapter == before.adapter)
        #expect(enabled.isCharging == before.isCharging)
    }

    @Test func missingTelemetryDoesNotUseAdapterRatingOrComputedBatteryPower() throws {
        let raw: [String: Any] = [
            "AdapterDetails": ["Watts": 140], "Voltage": 12_000, "Amperage": -1_000
        ]
        #expect(PowerFlowTelemetry.parse(from: raw, readAt: readAt) == nil)
        let partial = try #require(PowerFlowTelemetry.parse(
            from: props(input: nil, load: 12_000, battery: nil), readAt: readAt))
        #expect(partial.inputWatts == nil)
        #expect(partial.systemLoadWatts == 12)
        #expect(partial.batteryPowerWatts == nil)
        #expect(partial.batteryDirection == .unknown)
    }

    @Test func malformedAndPartialDictionariesRemainUnknown() throws {
        #expect(PowerFlowTelemetry.parse(from: ["PowerTelemetryData": "invalid"], readAt: readAt) == nil)
        let empty = try #require(PowerFlowTelemetry.parse(from: ["PowerTelemetryData": [:]], readAt: readAt))
        #expect(empty.inputWatts == nil)
        #expect(empty.systemLoadWatts == nil)
        #expect(empty.batteryPowerWatts == nil)
        #expect(empty.batteryDirection == .unknown)
    }

    @Test func invalidNumbersNeverBecomeZeroReadings() throws {
        let invalid: [Any] = [true, "14099", 1.5, Double.nan, Double.infinity,
                              NSNumber(value: UInt64.max), NSNumber(value: UInt64(1) << 63),
                              4_294_966_646, 1_000_001]
        for value in invalid {
            let flow = try #require(PowerFlowTelemetry.parse(
                from: props(input: value, load: value, battery: value), readAt: readAt))
            #expect(flow.inputWatts == nil)
            #expect(flow.systemLoadWatts == nil)
            #expect(flow.batteryPowerWatts == nil)
        }
        let negative = try #require(PowerFlowTelemetry.parse(
            from: props(input: -1_000, load: -1_000, battery: -1_000), readAt: readAt))
        #expect(negative.inputWatts == nil)
        #expect(negative.systemLoadWatts == nil)
        #expect(negative.batteryPowerWatts == -1)
    }

    @Test func statusMustBeExplicitAndConsistent() throws {
        for raw in [
            props(charging: nil), props(external: nil), props(current: nil),
            props(charging: 0), props(external: "true"), props(current: true),
            props(charging: true, current: -1_000),
            props(charging: true, external: false, current: 1_000),
            props(charging: false, current: 1_000), props(current: 1_000_000),
            props(battery: -12_000, charging: true, current: 1_000),
            props(battery: 12_000, charging: false, current: -1_000),
            props(battery: 0, charging: false, current: -1_000)
        ] {
            let flow = try #require(PowerFlowTelemetry.parse(from: raw, readAt: readAt))
            #expect(flow.batteryDirection == .unknown)
        }
    }

    @Test func signedBatteryPowerAndWrappedIntegersPreserveDirection() throws {
        let charging = try #require(PowerFlowTelemetry.parse(
            from: props(battery: 12_000, charging: true, current: 1_000), readAt: readAt))
        #expect(charging.batteryPowerWatts == 12)
        #expect(charging.batteryDirection == .charging)

        for external in [true, false] {
            for power: Any in [-12_000, NSNumber(value: UInt64(bitPattern: Int64(-12_000)))] {
                let discharging = try #require(PowerFlowTelemetry.parse(
                    from: props(battery: power, external: external, current: 4_294_966_296), readAt: readAt))
                #expect(discharging.batteryPowerWatts == -12)
                #expect(discharging.batteryDirection == .discharging)
            }
        }
    }

    @Test func registryReadFreshnessCannotClaimHardwareSampleFreshness() throws {
        let flow = try #require(PowerFlowTelemetry.parse(from: props(), readAt: readAt))
        #expect(!flow.isStale(at: readAt.addingTimeInterval(30)))
        #expect(flow.isStale(at: readAt.addingTimeInterval(31)))
        #expect(flow.isStale(at: readAt.addingTimeInterval(-1)))
        #expect(flow.isStale(at: readAt, maximumAge: -1))
        #expect(flow.isStale(at: readAt, maximumAge: .nan))
    }

    @Test func repeatedReadsPreserveReportedRegistryUpdateTime() throws {
        let updatedAt = readAt.addingTimeInterval(-37)
        let raw = props(updateTime: updatedAt.timeIntervalSince1970)
        let first = try #require(PowerFlowTelemetry.parse(from: raw, readAt: readAt))
        let nextReadAt = readAt.addingTimeInterval(10)
        let next = try #require(PowerFlowTelemetry.parse(from: raw, readAt: nextReadAt))
        #expect(first.registryUpdatedAt == updatedAt)
        #expect(next.registryUpdatedAt == updatedAt)
        #expect(next.readAt == nextReadAt)
        #expect(first.hasSameReadings(as: next))
    }

    @Test func invalidOrMissingRegistryUpdateTimeRemainsUnknown() throws {
        let missing = try #require(PowerFlowTelemetry.parse(from: props(), readAt: readAt))
        #expect(missing.registryUpdatedAt == nil)
        let invalid: [Any] = [true, "1700000000", Double.nan, Double.infinity,
                              -1, 946_684_799, readAt.timeIntervalSince1970 + 6,
                              NSNumber(value: UInt64.max)]
        for value in invalid {
            let flow = try #require(PowerFlowTelemetry.parse(
                from: props(updateTime: value), readAt: readAt))
            #expect(flow.registryUpdatedAt == nil)
            #expect(flow.inputWatts == 14.099)
        }
    }

    @Test func registryUpdateTimeAcceptsPlausibleNumericEpochs() throws {
        for seconds in [946_684_800, readAt.timeIntervalSince1970 - 0.5,
                        readAt.timeIntervalSince1970 + 5] {
            let flow = try #require(PowerFlowTelemetry.parse(
                from: props(updateTime: seconds), readAt: readAt))
            #expect(flow.registryUpdatedAt == Date(timeIntervalSince1970: seconds))
        }
    }

    @Test func registryUpdateChangesAreNotDeduplicatedWithEqualWatts() throws {
        let first = BatteryReader.snapshot(
            from: props(updateTime: readAt.timeIntervalSince1970 - 60),
            iops: nil, now: readAt, includePowerFlow: true)
        let next = BatteryReader.snapshot(
            from: props(updateTime: readAt.timeIntervalSince1970),
            iops: nil, now: readAt, includePowerFlow: true)
        let firstFlow = try #require(first.powerFlow)
        let nextFlow = try #require(next.powerFlow)
        #expect(firstFlow.inputWatts == nextFlow.inputWatts)
        #expect(!firstFlow.hasSameReadings(as: nextFlow))
        #expect(!first.hasSameReadings(as: next))
    }

    @Test func comparisonsIgnoreReadTimeButIncludeFlowChangesAndAvailability() {
        let first = BatteryReader.snapshot(from: props(), iops: nil, now: readAt, includePowerFlow: true)
        let later = BatteryReader.snapshot(
            from: props(), iops: nil, now: readAt.addingTimeInterval(10), includePowerFlow: true)
        #expect(first != later)
        #expect(first.hasSameReadings(as: later))
        for changed in [props(input: 15_000), props(load: 13_000), props(battery: 1_000),
                        props(input: nil), props(charging: nil)] {
            let next = BatteryReader.snapshot(from: changed, iops: nil, now: readAt, includePowerFlow: true)
            #expect(!first.hasSameReadings(as: next))
        }
        let disabled = BatteryReader.snapshot(from: props(), iops: nil, now: readAt)
        #expect(!first.hasSameReadings(as: disabled))
    }
}
