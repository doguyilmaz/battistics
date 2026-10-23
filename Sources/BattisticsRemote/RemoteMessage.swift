import Foundation

public struct RemoteRequest: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable { case status, start, stop }

    public var version = 1
    public var token: String
    public var operation: Operation
    public var mode: RemoteStatus.Mode?
    public var durationMinutes: Int?
    /// Shown on the Mac next to the session, e.g. the phone's name.
    public var deviceName: String?

    public init(token: String, operation: Operation, mode: RemoteStatus.Mode? = nil,
                durationMinutes: Int? = nil, deviceName: String? = nil) {
        self.token = token
        self.operation = operation
        self.mode = mode
        self.durationMinutes = durationMinutes
        self.deviceName = deviceName
    }

    /// The same finite choices the Mac offers: open-ended sessions cannot be
    /// started from a phone that may lose its connection.
    public static let durations = [15, 30, 60, 120, 240, 360, 720]
}

public struct RemoteReply: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        case unauthorized, invalidRequest, busy, closedLidNotAllowed, helperUnavailable,
             protection, startFailed, rateLimited, unavailable
    }

    public struct Failure: Codable, Sendable, Equatable {
        public var code: Code
        public var message: String
        public init(code: Code, message: String) { self.code = code; self.message = message }
    }

    public var status: RemoteStatus?
    public var error: Failure?

    public init(status: RemoteStatus) { self.status = status }
    public init(_ code: Code, _ message: String, status: RemoteStatus? = nil) {
        error = .init(code: code, message: message)
        self.status = status
    }
}

/// One JSON object per line, both ways, one exchange per connection.
public enum RemoteWire {
    public static let maximumBytes = 16_384
    public static let defaultPort: UInt16 = 47_616

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value) + Data([10])
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let line = data.last == 10 ? data.dropLast() : data[...]
        return try decoder.decode(type, from: Data(line))
    }
}
