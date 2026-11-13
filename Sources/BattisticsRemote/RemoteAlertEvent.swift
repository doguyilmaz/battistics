import Foundation

/// Retries reuse the same CloudKit record id, so an uncertain save cannot
/// produce a second record-creation push. Saved alongside the alert latch.
public struct RemoteAlertEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let alert: RemoteAlert
    public let createdAt: Date
    public let sessionStartedAt: Date?
    public let endedAt: Date?

    public init(alert: RemoteAlert, status: RemoteStatus, id: String = UUID().uuidString) {
        self.id = id
        self.alert = alert
        createdAt = status.readAt
        sessionStartedAt = status.session?.startedAt
        endedAt = status.lastEnd?.at
    }

    public func isRelevant(to status: RemoteStatus) -> Bool {
        guard (0..<600).contains(status.readAt.timeIntervalSince(createdAt)) else { return false }
        switch alert {
        case .runningHot:
            return status.session?.startedAt == sessionStartedAt && status.session != nil && status.thermal.isHot
        case .batteryLow:
            return status.battery.map { !$0.onAdapter && $0.percent <= status.protection.lowBatteryPercent } ?? false
        case .batteryRunsOut:
            return status.session?.startedAt == sessionStartedAt && status.batteryRunsOutFirst
        case .unpluggedWithoutHotspot, .closedLidWithoutHotspot:
            return status.session?.startedAt == sessionStartedAt && status.session != nil
                && status.battery?.onAdapter == false && status.network == .wifi
        case .sessionEnded:
            return status.session == nil && status.lastEnd?.at == endedAt
        case .sleptDuringSession:
            return status.sleptAt != nil
        case .bagReady, .chargeReached, .unreachable:
            return false
        }
    }
}
