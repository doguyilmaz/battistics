import Foundation

/// What the phone notifies about, decided from two readings of one Mac. Each
/// alert fires once when its condition starts, never on every refresh.
public enum RemoteAlert: Equatable, Sendable {
    case sessionEnded(RemoteStatus.EndReason?)
    case batteryLow(percent: Int)
    case batteryRunsOut(minutesLeft: Int)
    case unpluggedWithoutHotspot
    case closedLidWithoutHotspot
    case unreachable

    /// `current` is nil when the Mac did not answer; `previous` is nil before
    /// the first reading and `.some(nil)` after an unanswered one.
    public static func alerts(from previous: RemoteStatus??, to current: RemoteStatus?) -> [RemoteAlert] {
        switch (previous, current) {
        case (.some(.some(let previous)), .some(let current)): changes(from: previous, to: current)
        case (.some(.some(let previous)), .none): previous.session != nil ? [.unreachable] : []
        default: []
        }
    }

    private static func changes(from previous: RemoteStatus, to current: RemoteStatus) -> [RemoteAlert] {
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
            if current.session != nil, current.network == .wifi {
                if previous.battery?.onAdapter == true,
                   current.session?.mode == .lidClosed || current.lidClosed == true {
                    alerts.append(.unpluggedWithoutHotspot)
                } else if current.lidClosed == true, previous.lidClosed == false {
                    alerts.append(.closedLidWithoutHotspot)
                }
            }
        }
        return alerts
    }
}
