import Foundation

/// Observed only after a successful iCloud read. A missed push or failed
/// fetch cannot establish that the Mac has stopped publishing.
public struct RemoteSilenceState: Codable, Sendable, Equatable {
    public static let confirmationInterval: TimeInterval = 120
    public static let recoveryInterval: TimeInterval = 10 * 60

    private var sessionStartedAt: Date?
    private var staleReadAt: Date?
    private var firstStaleObservation: Date?
    private var lastObservation: Date?
    private var lastFreshReadAt: Date?
    private var recoveredSince: Date?
    private var alerted = false

    public init() {}

    /// True once two successful reads, at least two minutes apart, found
    /// the same status more than 30 minutes old during a running session.
    public mutating func observe(_ status: RemoteStatus, now: Date = .now) -> Bool {
        guard let session = status.session, session.isActive(at: now), status.sleptAt == nil else {
            self = Self()
            return false
        }
        if sessionStartedAt != session.startedAt {
            self = Self()
            sessionStartedAt = session.startedAt
        }
        if let lastObservation, now < lastObservation { interrupt() }
        let gap = lastObservation.map { now.timeIntervalSince($0) }
        defer { lastObservation = now }

        if status.isFresh(at: now) {
            staleReadAt = nil
            firstStaleObservation = nil
            if lastFreshReadAt == nil || gap.map({ $0 > status.heartbeatSeconds * 4 }) == true {
                recoveredSince = now
            }
            if let lastFreshReadAt, status.readAt > lastFreshReadAt,
               let recoveredSince, now.timeIntervalSince(recoveredSince) >= Self.recoveryInterval {
                alerted = false
            }
            lastFreshReadAt = status.readAt
            return false
        }

        recoveredSince = nil
        lastFreshReadAt = nil
        guard now >= status.unheardDate else {
            firstStaleObservation = nil
            return false
        }
        guard staleReadAt == status.readAt, let firstStaleObservation else {
            staleReadAt = status.readAt
            firstStaleObservation = now
            return false
        }
        guard !alerted, now.timeIntervalSince(firstStaleObservation) >= Self.confirmationInterval else { return false }
        alerted = true
        return true
    }

    /// Network failures, unreadable records and app suspension interrupt
    /// confirmation and recovery, without granting another alert.
    public mutating func interrupt() {
        staleReadAt = nil
        firstStaleObservation = nil
        lastObservation = nil
        lastFreshReadAt = nil
        recoveredSince = nil
    }
}
