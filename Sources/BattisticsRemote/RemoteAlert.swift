import Foundation

/// What the phone notifies about, decided from two readings of one Mac. Each
/// alert fires once when its condition starts, never on every refresh.
public enum RemoteAlert: Equatable, Sendable {
    case sessionEnded(RemoteStatus.EndReason?)
    case batteryLow(percent: Int)
    case batteryRunsOut(minutesLeft: Int)
    case unpluggedWithoutHotspot
    case closedLidWithoutHotspot
    case chargeReached(percent: Int)
    case unreachable

    public enum Kind: String, Sendable {
        case ended, battery, runtime, unplugged, closedlid, charged, silent
    }

    /// One notification per kind and Mac: a newer one replaces the older.
    public var kind: Kind {
        switch self {
        case .sessionEnded: .ended
        case .batteryLow: .battery
        case .batteryRunsOut: .runtime
        case .unpluggedWithoutHotspot: .unplugged
        case .closedLidWithoutHotspot: .closedlid
        case .chargeReached: .charged
        case .unreachable: .silent
        }
    }

    /// Kinds the Mac notices itself. The charge target is the phone's own
    /// setting, and only a phone can tell that the Mac stopped answering.
    public static let pushedKinds: Set<Kind> = [.ended, .battery, .runtime, .unplugged, .closedlid]

    /// What the Mac posts after publishing `current` over `previous`.
    public static func pushed(from previous: RemoteStatus, to current: RemoteStatus) -> [RemoteAlert] {
        changes(from: previous, to: current, chargeTarget: nil).filter { pushedKinds.contains($0.kind) }
    }

    /// `current` is nil when the Mac did not answer; `previous` is nil before
    /// the first reading and `.some(nil)` after an unanswered one.
    /// `chargeTarget` is the charge level the user wants to hear about while the Mac charges.
    public static func alerts(from previous: RemoteStatus??, to current: RemoteStatus?,
                              chargeTarget: Int? = nil) -> [RemoteAlert] {
        switch (previous, current) {
        case (.some(.some(let previous)), .some(let current)): changes(from: previous, to: current, chargeTarget: chargeTarget)
        case (.some(.some(let previous)), .none): previous.session != nil ? [.unreachable] : []
        default: []
        }
    }

    private static func changes(from previous: RemoteStatus, to current: RemoteStatus, chargeTarget: Int?) -> [RemoteAlert] {
        var alerts: [RemoteAlert] = []
        if let chargeTarget, let battery = current.battery, battery.onAdapter,
           battery.percent >= chargeTarget, let before = previous.battery, before.percent < chargeTarget {
            alerts.append(.chargeReached(percent: battery.percent))
        }
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
