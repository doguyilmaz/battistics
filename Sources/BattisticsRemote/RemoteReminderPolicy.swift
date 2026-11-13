import Foundation

/// Only a known, user-selected deadline can schedule a notification ahead.
/// Automatic task leases and missing telemetry are not reminder events.
public enum RemoteReminderPolicy {
    public static let endingLead: TimeInterval = 5 * 60

    public static func endingDate(for status: RemoteStatus, now: Date = .now) -> Date? {
        guard status.sleptAt == nil, let session = status.session,
              session.origin != .ai, session.origin != .terminal,
              let deadline = session.deadline else { return nil }
        let date = deadline.addingTimeInterval(-endingLead)
        return date.timeIntervalSince(now) > 1 ? date : nil
    }
}
