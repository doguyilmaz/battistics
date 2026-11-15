import Foundation

enum NearbyPacket: Codable, Sendable {
    case challenge(Data)
    case authenticate(nonce: Data, proof: Data)
    case encrypted(sequence: UInt64, body: Data)
}
