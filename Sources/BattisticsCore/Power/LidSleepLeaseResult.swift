/// Stable, semantic outcomes for the closed-lid lease XPC interface.
public enum LidSleepLeaseResult: Int32, Sendable {
    case success = 0
    case ownershipLost = 1
    case inactive = 2
    case unavailable = 3
    case rejected = 4
    case failed = 5
}
