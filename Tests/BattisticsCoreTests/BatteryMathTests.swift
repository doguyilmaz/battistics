import Foundation
import Testing

@testable import BattisticsCore

@Suite("Battery snapshot math")
struct BatteryMathTests {
    private func makeSnapshot(
        percent: Int = 80,
        rawMax: Int = 5941,
        nominal: Int? = 5900,
        design: Int = 6075,
        voltageMV: Int? = 12070,
        amperageMA: Int? = -650,
        isCharging: Bool = false,
        externalConnected: Bool = false,
        fullyCharged: Bool = false,
        avgTimeToEmptyMin: Int? = 312,
        avgTimeToFullMin: Int? = nil
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            batteryInstalled: true,
            percent: percent,
            rawCurrentCapacity: 4387,
            rawMaxCapacity: rawMax,
            nominalCapacity: nominal,
            designCapacity: design,
            cycleCount: 47,
            designCycleCount: 1000,
            temperatureC: 34.5,
            voltageMV: voltageMV,
            amperageMA: amperageMA,
            isCharging: isCharging,
            externalConnected: externalConnected,
            fullyCharged: fullyCharged,
            avgTimeToEmptyMin: avgTimeToEmptyMin,
            avgTimeToFullMin: avgTimeToFullMin,
            systemTimeRemainingMin: nil,
            systemHealthStatus: nil,
            serialNumber: nil,
            deviceName: nil,
            manufactureDate: nil,
            adapter: nil
        )
    }

    @Test func healthPercentPrefersNominalToMatchSystemSettings() {
        // nominal 5900 / design 6075
        let snapshot = makeSnapshot()
        #expect(abs(snapshot.healthPercent - 97.12) < 0.01)
        #expect(snapshot.currentMaxCapacity == 5900)
        // measured uses rawMax 5941 / design 6075
        #expect(abs(snapshot.measuredHealthPercent - 97.79) < 0.01)
        #expect(snapshot.healthStatus == .good)
    }

    @Test func youngPackGaugesAboveDesignButNeverDisplaysAboveHundred() {
        // DesignCapacity is a nameplate minimum, so a young pack really does
        // measure above it. macOS clamps; Battistics must not contradict it.
        let young = makeSnapshot(nominal: 6200, design: 6075)
        #expect(abs(young.healthPercent - 102.06) < 0.01)
        #expect(young.displayHealthPercent == 100)
    }

    @Test func displayHealthLeavesAnAgedPackUntouched() {
        let aged = makeSnapshot(nominal: 5371, design: 6075)
        #expect(abs(aged.displayHealthPercent - 88.41) < 0.01)
    }

    @Test func healthPointClampsForDisplayAndKeepsWhatWasRecorded() {
        let point = HealthPoint(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            healthPercent: 103.4, rawMaxCapacity: 6280, cycleCount: 12)
        #expect(point.healthPercent == 103.4)
        #expect(point.displayHealthPercent == 100)
    }

    /// Five consecutive days recorded on a real M-series Mac. The controller
    /// re-estimates NominalChargeCapacity daily, so the reading swings 3.6
    /// points with no actual degradation behind it.
    private static let observedDailyHealth = [89.37, 87.97, 87.11, 86.12, 89.73]

    @Test func medianIsUnmovedByASingleOutlier() {
        #expect(BatteryHealth.median([88, 88.5, 89]) == 88.5)
        #expect(BatteryHealth.median([88, 89]) == 88.5)
        #expect(BatteryHealth.median([]) == nil)
        let withOutlier = BatteryHealth.median(Self.observedDailyHealth)
        #expect(withOutlier == 87.97)
    }

    @Test func rollingMedianFlattensTheDailyGaugeSwing() {
        let smoothed = BatteryHealth.rollingMedian(Self.observedDailyHealth, window: 3)
        #expect(smoothed.count == Self.observedDailyHealth.count)

        let rawSpread = Self.observedDailyHealth.max()! - Self.observedDailyHealth.min()!
        #expect(abs(rawSpread - 3.61) < 0.01)

        // The first entries average fewer than `window` samples, so judge the
        // warmed-up tail: that is what the chart line actually looks like.
        let steady = smoothed.dropFirst(2)
        #expect(steady.max()! - steady.min()! < 1.0)
    }

    @Test func healthStatusBoundaries() {
        #expect(HealthStatus(healthPercent: 80) == .good)
        #expect(HealthStatus(healthPercent: 79.9) == .fair)
        #expect(HealthStatus(healthPercent: 60) == .fair)
        #expect(HealthStatus(healthPercent: 59.9) == .poor)
    }

    @Test func wattsIsSignedVoltsTimesAmps() {
        let snapshot = makeSnapshot()
        let watts = try! #require(snapshot.watts)
        #expect(abs(watts - (-7.8455)) < 0.001)
    }

    @Test func timeRemainingPicksSideByState() {
        let discharging = makeSnapshot(avgTimeToEmptyMin: 312)
        #expect(discharging.timeRemainingMin == 312)

        let charging = makeSnapshot(
            isCharging: true, externalConnected: true,
            avgTimeToEmptyMin: nil, avgTimeToFullMin: 84)
        #expect(charging.timeRemainingMin == 84)

        let idle = makeSnapshot(externalConnected: true)
        #expect(idle.timeRemainingMin == nil)
    }

    @Test func settlingSentinelIsRejected() {
        let settling = makeSnapshot(avgTimeToEmptyMin: 65535)
        #expect(settling.timeRemainingMin == nil)
    }

    @Test func signedMilliampsUnwrapsTwosComplement() {
        #expect(BatteryReader.signedMilliamps(4_294_966_646) == -650)
        #expect(BatteryReader.signedMilliamps(-650) == -650)
        #expect(BatteryReader.signedMilliamps(1200) == 1200)
        #expect(BatteryReader.signedMilliamps(nil) == nil)
    }

    @Test func smbusManufactureDateDecodes() {
        // 7 Dec 2021: ((2021-1980) << 9) | (12 << 5) | 7
        let packed = (41 << 9) | (12 << 5) | 7
        let date = try! #require(BatteryReader.manufactureDate(fromSMBus: packed))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2021)
        #expect(components.month == 12)
        #expect(components.day == 7)
    }

    @Test func smbusManufactureDateRejectsGarbage() {
        #expect(BatteryReader.manufactureDate(fromSMBus: 0) == nil)
        #expect(BatteryReader.manufactureDate(fromSMBus: 0xFFFF) == nil)
    }

    @Test func manufactureDateFromSerialWeekCode() {
        // F8Y|1|49|... = week 49 of 2021 (early December).
        let now = Date(timeIntervalSince1970: 1_786_307_126)  // Aug 2026
        let date = try! #require(
            BatteryReader.manufactureDate(fromSerial: "F8Y14920EWMQ1LTAL", now: now))
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month], from: date)
        #expect(components.year == 2021)
        #expect(components.month == 12)
    }

    @Test func manufactureDateFromSerialRejectsBadWeek() {
        #expect(BatteryReader.manufactureDate(fromSerial: "F8Y19920EWMQ1LTAL") == nil)
        #expect(BatteryReader.manufactureDate(fromSerial: "F8Y") == nil)
        #expect(BatteryReader.manufactureDate(fromSerial: "F8YX4920EWMQ1LTAL") == nil)
        // Short randomized device serials must never fabricate a date.
        #expect(BatteryReader.manufactureDate(fromSerial: "XK92JQW3AB") == nil)
    }

    @Test func percentClampsAboveHundred() {
        let props: [String: Any] = [
            "CurrentCapacity": 6000, "MaxCapacity": 5941,
            "AppleRawCurrentCapacity": 6000, "AppleRawMaxCapacity": 5941,
            "DesignCapacity": 6075, "CycleCount": 47,
        ]
        let snapshot = BatteryReader.snapshot(from: props, iops: nil, now: Date())
        #expect(snapshot.percent == 100)
    }

    @Test func opaqueManufactureDateBlobFallsBackToSerial() {
        let props: [String: Any] = [
            "CurrentCapacity": 80, "MaxCapacity": 100,
            "AppleRawCurrentCapacity": 4387, "AppleRawMaxCapacity": 5791,
            "DesignCapacity": 6075, "CycleCount": 47,
            "Serial": "F8Y14920EWMQ1LTAL",
            "BatteryData": ["ManufactureDate": 54_083_070_277_938] as [String: Any],
        ]
        let now = Date(timeIntervalSince1970: 1_786_307_126)
        let snapshot = BatteryReader.snapshot(from: props, iops: nil, now: now)
        let date = try! #require(snapshot.manufactureDate)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.year, from: date) == 2021)
    }

    @Test func appleHealthParsesSystemProfilerJSON() {
        let json = """
            {"SPPowerDataType": [
              {"_name": "spbattery_information",
               "sppower_battery_health_info": {
                 "sppower_battery_cycle_count": 47,
                 "sppower_battery_health": "Good",
                 "sppower_battery_health_maximum_capacity": "92"}},
              {"_name": "sppower_ac_charger_information"}
            ]}
            """.data(using: .utf8)!
        let info = try! #require(AppleHealthReader.parse(json))
        #expect(info.maximumCapacityPercent == 92)
        #expect(info.condition == "Good")
        #expect(AppleHealthReader.parse(Data("nonsense".utf8)) == nil)
    }

    @Test func temperaturePrefersVirtualReading() {
        let props: [String: Any] = [
            "CurrentCapacity": 80, "MaxCapacity": 100,
            "AppleRawCurrentCapacity": 4387, "AppleRawMaxCapacity": 5791,
            "DesignCapacity": 6075, "CycleCount": 47,
            "Temperature": 3062, "VirtualTemperature": 3300,
        ]
        let snapshot = BatteryReader.snapshot(from: props, iops: nil, now: Date())
        #expect(snapshot.temperatureC == 33.0)
        #expect(snapshot.cellTemperatureC == 30.62)
    }

    @Test func snapshotParsingFromRegistryDictionary() {
        let props: [String: Any] = [
            "CurrentCapacity": 80,
            "MaxCapacity": 100,
            "AppleRawCurrentCapacity": 4387,
            "AppleRawMaxCapacity": 5941,
            "NominalChargeCapacity": 5900,
            "DesignCapacity": 6075,
            "CycleCount": 47,
            "Temperature": 3450,
            "Voltage": 12070,
            "Amperage": -650,
            "IsCharging": false,
            "ExternalConnected": true,
            "FullyCharged": false,
            "Serial": "F8Y1234ABCD",
            "AdapterDetails": ["Watts": 96, "Name": "96W USB-C Power Adapter"] as [String: Any],
        ]
        let snapshot = BatteryReader.snapshot(from: props, iops: nil, now: Date())
        #expect(snapshot.percent == 80)
        #expect(snapshot.rawMaxCapacity == 5941)
        #expect(snapshot.temperatureC == 34.5)
        #expect(snapshot.adapter?.watts == 96)
        #expect(snapshot.externalConnected)
        #expect(!snapshot.isCharging)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func temperatureUnits() {
        #expect(Formatting.temperature(34.5, unit: .celsius) == "34.5°C")
        #expect(Formatting.temperature(34.5, unit: .fahrenheit) == "94.1°F")
        #expect(Formatting.temperature(34.5, unit: .both) == "34.5°C / 94.1°F")
    }

    @Test func durations() {
        #expect(Formatting.duration(minutes: 134) == "2h 14m")
        #expect(Formatting.duration(minutes: 45) == "45m")
        #expect(Formatting.clock(minutes: 134) == "2:14")
        #expect(Formatting.clock(minutes: 5) == "0:05")
    }

    @Test func age() {
        let fourYearsAgo = Date().addingTimeInterval(-4.7 * 365.25 * 24 * 3600)
        #expect(Formatting.age(from: fourYearsAgo) == "4.7 years")
        let eightMonthsAgo = Date().addingTimeInterval(-8 * 30.44 * 24 * 3600)
        #expect(Formatting.age(from: eightMonthsAgo) == "8 months")
    }
}
