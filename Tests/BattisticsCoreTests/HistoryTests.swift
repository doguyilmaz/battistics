import Foundation
import Testing

@testable import BattisticsCore

@Suite("History math")
struct HistoryMathTests {
    @Test func timeTotalsClassifyByLeadingSampleState() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            ChargeSample(date: base, percent: 90, externalConnected: false, isCharging: false),
            ChargeSample(date: base.addingTimeInterval(600), percent: 88, externalConnected: false, isCharging: false),
            ChargeSample(date: base.addingTimeInterval(1200), percent: 87, externalConnected: true, isCharging: true),
            ChargeSample(date: base.addingTimeInterval(1800), percent: 92, externalConnected: true, isCharging: true),
            ChargeSample(date: base.addingTimeInterval(2400), percent: 100, externalConnected: true, isCharging: false),
            ChargeSample(date: base.addingTimeInterval(3000), percent: 100, externalConnected: true, isCharging: false),
        ]
        let totals = HistoryMath.timeTotals(samples: samples)
        #expect(totals.onBattery == 1200)
        #expect(totals.charging == 1200)
        #expect(totals.fullyCharged == 600)
    }

    @Test func timeTotalsClampSleepGaps() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            ChargeSample(date: base, percent: 90, externalConnected: false, isCharging: false),
            // 8 hour gap (asleep): counts as at most maxGapSeconds.
            ChargeSample(date: base.addingTimeInterval(8 * 3600), percent: 85, externalConnected: false, isCharging: false),
        ]
        let totals = HistoryMath.timeTotals(samples: samples)
        #expect(totals.onBattery == HistoryMath.maxGapSeconds)
    }

    @Test func bucketedAverages() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            SeriesPoint(date: base, value: 10),
            SeriesPoint(date: base.addingTimeInterval(10), value: 20),
            SeriesPoint(date: base.addingTimeInterval(70), value: 40),
        ]
        let buckets = HistoryMath.bucketed(points: points, bucketSeconds: 60)
        #expect(buckets.count == 2)
        #expect(buckets[0].value == 15)
        #expect(buckets[1].value == 40)
    }
}

@Suite("History store", .serialized)
struct HistoryStoreTests {
    private func makeStore() -> HistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("battistics-tests-\(UUID().uuidString)")
        return HistoryStore(directory: directory)
    }

    @Test func recordsAndQueriesChargeSeries() async {
        let store = makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<10 {
            await store.recordChargeSample(
                ChargeSample(
                    date: base.addingTimeInterval(Double(i) * 300),
                    percent: 90 - i,
                    externalConnected: false,
                    isCharging: false
                ))
        }
        let series = await store.chargeSeries(
            from: base, to: base.addingTimeInterval(3600), bucketSeconds: 600)
        #expect(!series.isEmpty)
        let totals = await store.timeTotals(from: base, to: base.addingTimeInterval(3600))
        #expect(totals.onBattery == 9 * 300)
    }

    @Test func healthSnapshotOncePerDayAndPreviousReturned() async {
        let store = makeStore()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(24 * 3600)

        let first = await store.recordHealthSnapshot(
            date: day1, healthPercent: 95, rawMaxCapacity: 5800, nominalCapacity: nil,
            designCapacity: 6075, cycleCount: 100)
        #expect(first.isEmpty)
        #expect(await store.hasHealthSnapshot(forDay: day1))
        #expect(!(await store.hasHealthSnapshot(forDay: day2)))

        let baseline = await store.recordHealthSnapshot(
            date: day2, healthPercent: 94.5, rawMaxCapacity: 5770, nominalCapacity: nil,
            designCapacity: 6075, cycleCount: 101)
        #expect(baseline == [95])

        let series = await store.healthSeries()
        #expect(series.count == 2)
        #expect(series[0].healthPercent == 95)
    }

    @Test func lastUnplugDateFindsTransition() async {
        let store = makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.recordChargeSample(ChargeSample(date: base, percent: 100, externalConnected: true, isCharging: false))
        await store.recordChargeSample(
            ChargeSample(date: base.addingTimeInterval(600), percent: 99, externalConnected: false, isCharging: false))
        await store.recordChargeSample(
            ChargeSample(date: base.addingTimeInterval(1200), percent: 97, externalConnected: false, isCharging: false))

        let unplug = await store.lastUnplugDate()
        #expect(unplug == base.addingTimeInterval(600))
    }

    @Test func lastUnplugDateNilWhilePlugged() async {
        let store = makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.recordChargeSample(ChargeSample(date: base, percent: 50, externalConnected: false, isCharging: false))
        await store.recordChargeSample(
            ChargeSample(date: base.addingTimeInterval(600), percent: 55, externalConnected: true, isCharging: true))
        let unplug = await store.lastUnplugDate()
        #expect(unplug == nil)
    }

    @Test func retentionCollapsesOldPowerSamples() async {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-40 * 24 * 3600)
        for i in 0..<5 {
            await store.recordPowerSample(
                date: old.addingTimeInterval(Double(i) * 60), watts: 8 + Double(i),
                volts: 12, amps: -0.6, temperatureC: 31)
        }
        await store.recordPowerSample(date: now, watts: 5, volts: 12, amps: -0.4, temperatureC: 30)
        await store.runRetention(now: now)

        // Old raw samples are gone but still queryable through hourly rollups.
        let series = await store.powerSeries(
            from: old.addingTimeInterval(-3600), to: now.addingTimeInterval(3600), bucketSeconds: 3600)
        #expect(series.contains { abs($0.value - 10) < 0.001 })
        #expect(series.contains { abs($0.value - 5) < 0.001 })
    }

    @Test func csvRoundTripIncludesHourlyRollups() async throws {
        let store = makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.recordChargeSample(ChargeSample(date: base, percent: 88, externalConnected: false, isCharging: false))
        await store.recordPowerSample(date: base, watts: 7.5, volts: 12.07, amps: -0.62, temperatureC: 33.2)
        // A sample old enough for retention to compact it into power_hourly.
        await store.recordPowerSample(
            date: base.addingTimeInterval(-40 * 24 * 3600), watts: 9, volts: 12, amps: -0.7,
            temperatureC: 30)
        await store.runRetention(now: base)
        await store.recordHealthSnapshot(
            date: base, healthPercent: 97.8, rawMaxCapacity: 5941, nominalCapacity: 5900,
            designCapacity: 6075, cycleCount: 47)

        let csv = await store.exportCSV()
        #expect(csv.hasPrefix(CSVPort.header))
        #expect(csv.contains("\nhourly,"))

        let other = makeStore()
        let imported = try await other.importCSV(csv)
        #expect(imported == 4)

        let reExported = await other.exportCSV()
        #expect(reExported == csv)
    }

    @Test func csvImportsCRLFLineEndings() async throws {
        let store = makeStore()
        let crlf = "# Battistics history export v1\r\ncharge,1700000000,88,0,0\r\n"
        let imported = try await store.importCSV(crlf)
        #expect(imported == 1)
    }

    @Test func csvRejectsGarbage() async {
        let store = makeStore()
        await #expect(throws: HistoryError.self) {
            try await store.importCSV("nonsense,1,2,3\n")
        }
    }

    @Test func csvRejectsOutOfRangeTimestamps() async {
        let store = makeStore()
        // Would otherwise trap in the Int64 -> Date -> Int64 round trip.
        await #expect(throws: HistoryError.self) {
            try await store.importCSV("charge,9223372036854775807,50,0,0\n")
        }
        await #expect(throws: HistoryError.self) {
            try await store.importCSV("charge,-5,50,0,0\n")
        }
    }
}
