import Foundation

/// What the phone notifies about, decided from two readings of one Mac. Each
/// alert fires once when its condition starts, never on every refresh.
public enum RemoteAlert: Equatable, Sendable {
    case sessionEnded(RemoteStatus.EndReason?)
    case batteryLow(percent: Int)
    case batteryRunsOut(minutesLeft: Int)
    case unreachable

    /// A reading, or nil when the Mac did not answer.
    public static func alerts(from previous: RemoteStatus??, to current: RemoteStatus?) -> [RemoteAlert] {
        guard let previous else { return [] }
        guard let current else {
            return previous?.session != nil ? [.unreachable] : []
        }
        guard let previous else { return [] }
        var alerts: [RemoteAlert] = []
        if previous.session != nil, current.session == nil, current.lastEnd?.reason != .phone {
            alerts.append(.sessionEnded(current.lastEnd?.reason))
        }
        if let battery = current.battery, !battery.onAdapter {
            let threshold = current.protection.warnAtPercent ?? 20
            let wasAbove = previous.battery.map { $0.onAdapter || $0.percent > threshold } ?? true
            if battery.percent <= threshold, wasAbove { alerts.append(.batteryLow(percent: battery.percent)) }
            if current.batteryRunsOutFirst, !previous.batteryRunsOutFirst, let minutes = battery.minutesRemaining {
                alerts.append(.batteryRunsOut(minutesLeft: minutes))
            }
        }
        return alerts
    }
}
