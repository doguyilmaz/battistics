import Foundation

/// A Start or Stop sent from a phone through iCloud.
public struct RemoteRequest: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable { case start, stop }

    public var id: String
    public var operation: Operation
    public var mode: RemoteStatus.Mode?
    public var durationMinutes: Int?
    /// Shown on the Mac next to the session, e.g. the phone's name.
    public var deviceName: String?
    public var sentAt: Date

    public init(id: String = UUID().uuidString, operation: Operation, mode: RemoteStatus.Mode? = nil,
                durationMinutes: Int? = nil, deviceName: String? = nil, sentAt: Date = Date()) {
        self.id = id
        self.operation = operation
        self.mode = mode
        self.durationMinutes = durationMinutes
        self.deviceName = deviceName
        self.sentAt = sentAt
    }

    /// The same finite choices the Mac offers: open-ended sessions cannot be
    /// started from a phone that may lose its connection.
    public static let durations = [15, 30, 60, 120, 240, 360, 720]

    /// A command older than this is dropped unread: the phone has given up.
    public static let lifetime: TimeInterval = 120
}

public struct RemoteFailure: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        case invalidRequest, busy, closedLidNotAllowed, helperUnavailable, protection, startFailed, unavailable
    }

    public var code: Code
    public var message: String
    public init(_ code: Code, _ message: String) { self.code = code; self.message = message }
}

public enum RemoteWire {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(type, from: data)
    }
}
