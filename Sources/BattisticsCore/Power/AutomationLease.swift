import Foundation

/// One connection owns one bounded session. Renewal cannot revive an expired
/// lease or move its absolute deadline; stopping removes the lease entirely.
public struct AutomationLease: Sendable {
    public static let heartbeatInterval: TimeInterval = 15
    public static let timeout: TimeInterval = 45
    public let id: UUID
    public let owner: UUID
    public let name: String
    public let deadline: Date
    public private(set) var heartbeatDeadline: Date

    public init(id: UUID, owner: UUID, name: String, deadline: Date, now: Date) {
        self.id = id
        self.owner = owner
        self.name = name
        self.deadline = deadline
        heartbeatDeadline = min(deadline, now.addingTimeInterval(Self.timeout))
    }

    public func isExpired(at now: Date) -> Bool { now >= min(deadline, heartbeatDeadline) }

    @discardableResult
    public mutating func renew(id: UUID, owner: UUID, now: Date) -> Bool {
        guard self.id == id, self.owner == owner, !isExpired(at: now) else { return false }
        heartbeatDeadline = min(deadline, now.addingTimeInterval(Self.timeout))
        return true
    }
}
