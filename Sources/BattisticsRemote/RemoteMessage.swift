import Foundation

/// A command sent from a phone through iCloud.
public struct RemoteRequest: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable, TolerantWireValue {
        case start
        case stop
        case setLowPower
        case sleepDisplay
        /// Samples accessory batteries and the apps using the most energy, on request only.
        case inspect
        /// Adds `durationMinutes` to the running timed session.
        case extend
        /// Sent by a newer phone; answered as an invalid request instead of left unread.
        case unknown

        public static let fallback = Self.unknown
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

    /// The phone's name as the Mac shows it next to a session.
    public var senderName: String? {
        deviceName.map { String($0.prefix(64)) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Finite durations a phone may request; the app and Shortcuts each offer a subset.
    public static let durations = [15, 30, 60, 120, 240, 360, 720]

    /// What a phone may add to a running session at once.
    public static let extensions = [15, 30, 60, 120]

    /// All valid duration values including 0 (indefinite / until turned off).
    public static let allowedDurations: Set<Int> = Set(durations + [0])

    /// How long a phone waits for the Mac's answer before saying it did not come.
    public static let answerWait: TimeInterval = 36

    /// A command older than this is dropped unread: the phone has given up,
    /// and the margin covers two clocks a little apart.
    public static let lifetime: TimeInterval = answerWait + 24
}

public struct RemoteFailure: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable, TolerantWireValue {
        case invalidRequest, busy, closedLidNotAllowed, helperUnavailable, protection, startFailed, unavailable

        /// The phone shows the Mac's own words for a code it does not know.
        public static let fallback = Self.startFailed
    }

    public var code: Code
    /// The Mac's own words, shown only for `protection` and `startFailed`; the
    /// phone words every other code itself, in its own language.
    public var message: String
    public init(_ code: Code, _ message: String = "") { self.code = code; self.message = message }
}

/// A value a newer Mac or phone adds decodes as `fallback` on an older one,
/// so one new case never makes a whole message unreadable.
public protocol TolerantWireValue: RawRepresentable<String>, Decodable {
    static var fallback: Self { get }
}

extension TolerantWireValue {
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .fallback
    }
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
