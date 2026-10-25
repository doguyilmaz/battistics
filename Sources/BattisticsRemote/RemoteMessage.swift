import Foundation

/// A command sent from a phone through iCloud.
public struct RemoteRequest: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable {
        case start
        case stop
        case setLowPower
        case sleepDisplay
        /// Samples accessory batteries and the apps using the most energy, on request only.
        case inspect
        /// Sent by a newer phone; answered as an invalid request instead of left unread.
        case unknown

        public init(from decoder: Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var id: String
    public var operation: Operation
    public var mode: RemoteStatus.Mode?
    /// Duration in minutes; `0` or `nil` means "until turned off" (indefinite).
    public var durationMinutes: Int?
    /// Desired Low Power Mode policy when `operation == .setLowPower`.
    public var lowPowerPolicy: RemoteStatus.LowPowerPolicy?
    /// Shown on the Mac next to the session, e.g. the phone's name.
    public var deviceName: String?
    public var sentAt: Date

    public init(id: String = UUID().uuidString, operation: Operation, mode: RemoteStatus.Mode? = nil,
                durationMinutes: Int? = nil, lowPowerPolicy: RemoteStatus.LowPowerPolicy? = nil,
                deviceName: String? = nil, sentAt: Date = Date()) {
        self.id = id
        self.operation = operation
        self.mode = mode
        self.durationMinutes = durationMinutes
        self.lowPowerPolicy = lowPowerPolicy
        self.deviceName = deviceName
        self.sentAt = sentAt
    }

    /// Finite durations a phone may request; the app and Shortcuts each offer a subset.
    public static let durations = [15, 30, 60, 120, 240, 360, 720]

    /// All valid duration values including 0 (indefinite / until turned off).
    public static let allowedDurations: Set<Int> = Set(durations + [0])

    /// A command older than this is dropped unread: the phone has given up.
    public static let lifetime: TimeInterval = 120
}

public struct RemoteFailure: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        case invalidRequest, busy, closedLidNotAllowed, helperUnavailable, protection, startFailed, unavailable
    }

    public var code: Code
    /// The Mac's own words, shown only for `protection` and `startFailed`; the
    /// phone words every other code itself, in its own language.
    public var message: String
    public init(_ code: Code, _ message: String = "") { self.code = code; self.message = message }
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
