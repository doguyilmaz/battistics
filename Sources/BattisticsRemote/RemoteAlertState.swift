import Foundation

/// One instance per Mac, persisted by the sender. Brief recoveries must not
/// turn one ongoing problem into a new notification on every crossing.
public struct RemoteAlertState: Codable, Sendable, Equatable {
    public static let recoveryInterval: TimeInterval = 10 * 60

    private var sessionStartedAt: Date?
    private var sent: Set<String> = []
    private var recoveringSince: [String: Date] = [:]
    private var lastReadAt: Date?

    public init() {}

    public mutating func filter(_ alerts: [RemoteAlert], status: RemoteStatus) -> [RemoteAlert] {
        if let lastReadAt, status.readAt < lastReadAt { return [] }
        if let lastReadAt, status.readAt.timeIntervalSince(lastReadAt) > status.heartbeatSeconds * 4 {
            recoveringSince.removeAll()
        }
        lastReadAt = status.readAt
        if let start = status.session?.startedAt, start != sessionStartedAt {
            sessionStartedAt = start
            sent.subtract(["runtime", "network", "bagready", "ended", "asleep"])
        }

        let batteryRecovered = status.battery.map {
            (0...100).contains($0.percent)
                && ($0.onAdapter || $0.percent >= status.protection.lowBatteryPercent + 5)
        } ?? false
        rearm("battery", recovered: batteryRecovered, at: status.readAt)
        rearm("hot", recovered: !status.thermal.isHot, at: status.readAt)

        return alerts.filter { alert in
            // These have their own per-Mac latches on the phone: the charge
            // target rearms on a new charge, and silence needs read evidence.
            if alert.kind == .charged || alert == .unreachable { return true }
            let key = switch alert {
            case .unpluggedWithoutHotspot, .closedLidWithoutHotspot: "network"
            default: alert.kind.rawValue
            }
            return sent.insert(key).inserted
        }
    }

    private mutating func rearm(_ key: String, recovered: Bool, at date: Date) {
        guard recovered else {
            recoveringSince[key] = nil
            return
        }
        guard sent.contains(key) else { return }
        let since = recoveringSince[key] ?? date
        recoveringSince[key] = since
        if date.timeIntervalSince(since) >= Self.recoveryInterval {
            sent.remove(key)
            recoveringSince[key] = nil
        }
    }
}
