import Foundation

public enum NearbyError: Error, Sendable {
    case authentication
    case malformedFrame
    case unavailable
    case capacity
    case staleRequest
    case commandCollision
    case uncertainCommand
}
