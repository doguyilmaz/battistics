import Foundation

enum NearbyMessage: Codable, Sendable {
    case ready
    case read(id: UUID)
    case command(id: UUID, request: RemoteRequest)
    case status(id: UUID?, status: RemoteStatus)
    case acknowledged(UUID)
}
