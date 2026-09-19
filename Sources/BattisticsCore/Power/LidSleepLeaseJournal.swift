import Foundation

/// A rollback record is made terminal before deletion or any restoration.
/// An abandoned record can never authorize a write, even after a restart.
public struct LidSleepLeaseJournal: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case prepared, active, abandoned }

    public let version: Int
    public let original: Bool
    public let session: UUID?
    public var phase: Phase

    public init(original: Bool, session: UUID?, phase: Phase = .active) {
        version = 1
        self.original = original
        self.session = session
        self.phase = phase
    }

    public static func decode(_ data: Data) throws -> Self {
        // The old helper only wrote the original value, and always enforced true.
        if data == Data("0".utf8) { return Self(original: false, session: nil) }
        if data == Data("1".utf8) { return Self(original: true, session: nil) }
        let record = try JSONDecoder().decode(Self.self, from: data)
        guard record.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
