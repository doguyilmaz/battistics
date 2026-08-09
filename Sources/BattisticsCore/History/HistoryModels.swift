import Foundation

public struct SeriesPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct HealthPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let healthPercent: Double
    public let rawMaxCapacity: Int
    public let cycleCount: Int

    public var id: Date { date }

    public init(date: Date, healthPercent: Double, rawMaxCapacity: Int, cycleCount: Int) {
        self.date = date
        self.healthPercent = healthPercent
        self.rawMaxCapacity = rawMaxCapacity
        self.cycleCount = cycleCount
    }
}

public struct ChargeSample: Sendable, Equatable {
    public let date: Date
    public let percent: Int
    public let externalConnected: Bool
    public let isCharging: Bool

    public init(date: Date, percent: Int, externalConnected: Bool, isCharging: Bool) {
        self.date = date
        self.percent = percent
        self.externalConnected = externalConnected
        self.isCharging = isCharging
    }
}

public struct TimeTotals: Sendable, Equatable {
    public var onBattery: TimeInterval
    public var charging: TimeInterval
    public var fullyCharged: TimeInterval

    public init(onBattery: TimeInterval = 0, charging: TimeInterval = 0, fullyCharged: TimeInterval = 0) {
        self.onBattery = onBattery
        self.charging = charging
        self.fullyCharged = fullyCharged
    }
}

public enum HistoryMath {
    /// Any gap larger than this is clamped so sleep periods do not inflate
    /// the awake-time totals.
    public static let maxGapSeconds: TimeInterval = 900

    /// Classifies the interval after each sample by that sample's state.
    /// Plugged in but not charging counts as fully charged (trickle/hold).
    public static func timeTotals(samples: [ChargeSample]) -> TimeTotals {
        var totals = TimeTotals()
        guard samples.count > 1 else { return totals }
        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = min(next.date.timeIntervalSince(current.date), maxGapSeconds)
            guard gap > 0 else { continue }
            if !current.externalConnected {
                totals.onBattery += gap
            } else if current.isCharging {
                totals.charging += gap
            } else {
                totals.fullyCharged += gap
            }
        }
        return totals
    }

    /// Groups points into fixed buckets and averages them, newest-last.
    public static func bucketed(points: [SeriesPoint], bucketSeconds: TimeInterval) -> [SeriesPoint] {
        guard bucketSeconds > 0, !points.isEmpty else { return points }
        var sums: [TimeInterval: (total: Double, count: Int)] = [:]
        for point in points {
            let bucket = (point.date.timeIntervalSince1970 / bucketSeconds).rounded(.down) * bucketSeconds
            let entry = sums[bucket] ?? (0, 0)
            sums[bucket] = (entry.total + point.value, entry.count + 1)
        }
        return sums.keys.sorted().map { bucket in
            let entry = sums[bucket]!
            return SeriesPoint(
                date: Date(timeIntervalSince1970: bucket),
                value: entry.total / Double(entry.count)
            )
        }
    }
}
