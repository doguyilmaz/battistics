import CryptoKit
import Foundation

/// An account-owned capability, exchanged only through encrypted private CloudKit data.
/// It is kept out of RemoteStatus, widgets, defaults and diagnostic output.
public struct NearbyCredential: Codable, Sendable, Equatable {
    public let version: Int
    public let macID: String
    public let key: Data

    public init(macID: String, key: Data) throws {
        guard !macID.isEmpty, macID.utf8.count <= 128, key.count == 32 else { throw NearbyError.authentication }
        version = 1
        self.macID = macID
        self.key = key
    }

    public static func generate(macID: String) throws -> Self {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return try Self(macID: macID, key: key)
    }

    public var isValid: Bool { version == 1 && !macID.isEmpty && macID.utf8.count <= 128 && key.count == 32 }

    /// Opaque service identifier. No computer/account name is advertised.
    public var discoveryID: String {
        SHA256.hash(data: Data("Battistics nearby discovery v1".utf8) + key).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
    }

    public var serviceUUID: UUID {
        let id = discoveryID
        let characters = Array(id)
        let text = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(characters[$0]) }.joined(separator: "-")
        return UUID(uuidString: text)!
    }
}
