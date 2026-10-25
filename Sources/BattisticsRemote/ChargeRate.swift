import Foundation

/// How fast a battery filled or drained over the last hour, from readings
/// this device took itself.
public enum ChargeRate {
    /// Percent per hour, positive while charging. Nil without at least two
    /// readings spanning 15 minutes of the last 90, or under 1% per hour.
    public static func perHour(_ points: [RemoteStatus.ChargePoint], now: Date = .now) -> Double? {
        let recent = points.filter { now.timeIntervalSince($0.at) <= 90 * 60 }
        guard let first = recent.first, let last = recent.last else { return nil }
        let hours = last.at.timeIntervalSince(first.at) / 3600
        guard hours >= 0.25 else { return nil }
        let rate = (last.percent - first.percent) / hours
        return abs(rate) >= 1 ? rate : nil
    }

    /// Minutes until empty or full at `rate`, nil when the rate points the other way.
    public static func minutesLeft(percent: Int, rate: Double) -> Int? {
        let remaining = rate < 0 ? Double(percent) : Double(100 - percent)
        guard remaining > 0 else { return nil }
        return Int((remaining / abs(rate) * 60).rounded())
    }
}
