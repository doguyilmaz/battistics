import Foundation
import Testing
@testable import BattisticsCore

struct BatteryCapacityFallbackTests {
    @Test func nestedCapacitiesDoNotUseNormalizedPercentAsMilliamps() {
        let snapshot = BatteryReader.snapshot(from: [
            "CurrentCapacity": 80, "MaxCapacity": 100,
            "BatteryData": ["NominalChargeCapacity": 5100, "FullChargeCapacity": 5200,
                            "RemainingCapacity": 4160, "DesignCapacity": 6000]
        ], iops: nil, now: Date())
        #expect(snapshot.percent == 80)
        #expect(snapshot.rawCurrentCapacity == 4160)
        #expect(snapshot.rawMaxCapacity == 5200)
        #expect(snapshot.healthPercent == 85)
        #expect(snapshot.hasHealthReading)
    }

    @Test func missingPhysicalCapacitiesAreUnavailable() {
        let snapshot = BatteryReader.snapshot(from: [
            "CurrentCapacity": 80, "MaxCapacity": 100, "DesignCapacity": 6000
        ], iops: nil, now: Date())
        #expect(!snapshot.hasHealthReading)
        #expect(!snapshot.hasMeasuredHealthReading)
        #expect(snapshot.rawMaxCapacity == 0)
    }

    @Test func zeroTopLevelValuesFallBackToNestedValues() {
        let snapshot = BatteryReader.snapshot(from: [
            "NominalChargeCapacity": 0, "DesignCapacity": 0,
            "BatteryData": ["NominalChargeCapacity": 5100, "DesignCapacity": 6000]
        ], iops: nil, now: Date())
        #expect(snapshot.healthPercent == 85)
        #expect(!snapshot.hasMeasuredHealthReading)
    }
}
