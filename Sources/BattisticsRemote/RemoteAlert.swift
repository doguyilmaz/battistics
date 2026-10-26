import Foundation

/// What the phone notifies about, decided from two readings of one Mac. Each
/// alert fires once when its condition starts, never on every refresh.
public enum RemoteAlert: Equatable, Sendable {
    case sessionEnded(RemoteStatus.EndReason?)
    case batteryLow(percent: Int)
    case batteryRunsOut(minutesLeft: Int)
    case unpluggedWithoutHotspot
    case closedLidWithoutHotspot
    case runningHot
    /// A closed-lid session reached Personal Hotspot while the lid is still open.
    case bagReady
    case sleptDuringSession
    case chargeReached(percent: Int)
    case unreachable

    public enum Kind: String, Sendable {
        case ended, battery, runtime, unplugged, closedlid, hot, bagready, asleep, charged, silent

        /// Whether stopping Keep Awake answers this alert. A low battery is
        /// also reported without a session, when there is nothing to stop.
        public func offersStop(sessionRunning: Bool) -> Bool {
            switch self {
            case .runtime, .hot, .unplugged, .closedlid: true
            case .battery: sessionRunning
            default: false
            }
        }
    }

    /// One notification per kind and Mac: a newer one replaces the older.
    public var kind: Kind {
        switch self {
        case .sessionEnded: .ended
        case .batteryLow: .battery
        case .batteryRunsOut: .runtime
        case .unpluggedWithoutHotspot: .unplugged
        case .closedLidWithoutHotspot: .closedlid
        case .runningHot: .hot
        case .bagReady: .bagready
        case .sleptDuringSession: .asleep
        case .chargeReached: .charged
        case .unreachable: .silent
        }
    }

    /// Kinds the Mac notices itself. The charge target is the phone's own
    /// setting, and only a phone can tell that the Mac stopped answering.
    public static let pushedKinds: Set<Kind> = [.ended, .battery, .runtime, .unplugged, .closedlid, .hot, .bagready, .asleep]

    /// A Mac held at a charge limit tops up across the target again and
    /// again, so after one charge alert the next waits for the charge to fall
    /// 5 points below the target or for the adapter to be unplugged.
    public static func chargeAlertRearms(at status: RemoteStatus, target: Int) -> Bool {
        guard let battery = status.battery else { return false }
        return !battery.onAdapter || battery.percent <= target - 5
    }

    /// What the Mac posts after publishing `current` over `previous`.
    /// An end the Mac first reports long after it happened, having slept
    /// through it, is old news; a phone may only hear of one late.
    public static func pushed(from previous: RemoteStatus, to current: RemoteStatus) -> [RemoteAlert] {
        changes(from: previous, to: current, chargeTarget: nil).filter { alert in
            guard case .sessionEnded = alert, let end = current.lastEnd else { return true }
            return current.readAt.timeIntervalSince(end.at) < 10 * 60
        }
    }

    /// `current` is nil when the Mac did not answer; `previous` is nil before
    /// the first reading and `.some(nil)` after an unanswered one.
    /// `chargeTarget` is the charge level the user wants to hear about while the Mac charges.
    /// A Mac silent after its timed session ran out most likely slept before saying so.
    public static func alerts(from previous: RemoteStatus??, to current: RemoteStatus?,
                              chargeTarget: Int? = nil, now: Date = Date()) -> [RemoteAlert] {
        switch (previous, current) {
        case (.some(.some(let previous)), .some(let current)):
            // Nobody needs to hear that the Mac went to sleep hours ago.
            if let sleptAt = current.sleptAt, now.timeIntervalSince(sleptAt) > 10 * 60 { return [] }
            return changes(from: previous, to: current, chargeTarget: chargeTarget)
        case (.some(.some(let previous)), .none): return previous.session?.isActive(at: now) == true ? [.unreachable] : []
        default: return []
        }
    }

    private static func changes(from previous: RemoteStatus, to current: RemoteStatus, chargeTarget: Int?) -> [RemoteAlert] {
        // Sleeping says it all; a lid closing at the same moment is why.
        if current.sleptAt != nil, previous.sleptAt == nil, current.session?.isActive(at: current.readAt) == true {
            return [.sleptDuringSession]
        }
        var alerts: [RemoteAlert] = []
        if let chargeTarget, let battery = current.battery, battery.onAdapter,
           battery.percent >= chargeTarget, let before = previous.battery, before.percent < chargeTarget {
            alerts.append(.chargeReached(percent: battery.percent))
        }
        if previous.session != nil, current.session == nil, current.lastEnd?.reason != .phone {
            alerts.append(.sessionEnded(current.lastEnd?.reason))
        }
        if current.session != nil, current.thermal.isHot, !previous.thermal.isHot {
            alerts.append(.runningHot)
        }
        if current.session?.mode == .lidClosed, current.isBagReady, !previous.isBagReady, current.lidClosed != true {
            alerts.append(.bagReady)
        }
        if let battery = current.battery, !battery.onAdapter {
            let threshold = current.protection.lowBatteryPercent
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
