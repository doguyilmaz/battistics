import Foundation

/// Everything the phone shows about one Mac, read on the Mac in one pass.
public struct RemoteStatus: Codable, Sendable, Equatable {
    public struct Battery: Codable, Sendable, Equatable {
        public var percent: Int
        public var isCharging: Bool
        public var onAdapter: Bool
        /// Minutes to empty on battery, to full while charging.
        public var minutesRemaining: Int?
        public var healthPercent: Int?

        public init(percent: Int, isCharging: Bool, onAdapter: Bool,
                    minutesRemaining: Int? = nil, healthPercent: Int? = nil) {
            self.percent = percent
            self.isCharging = isCharging
            self.onAdapter = onAdapter
            self.minutesRemaining = minutesRemaining
            self.healthPercent = healthPercent
        }
    }

    public enum Mode: String, Codable, Sendable, CaseIterable {
        case displayOn, displayMaySleep, lidClosed
    }

    public enum Origin: String, Codable, Sendable {
        case manual, profile, terminal, ai, phone
    }

    public struct Session: Codable, Sendable, Equatable {
        public var mode: Mode
        public var origin: Origin
        public var name: String?
        public var startedAt: Date
        public var deadline: Date?

        public init(mode: Mode, origin: Origin, name: String? = nil, startedAt: Date, deadline: Date?) {
            self.mode = mode
            self.origin = origin
            self.name = name
            self.startedAt = startedAt
            self.deadline = deadline
        }
    }

    public enum EndReason: String, Codable, Sendable {
        case timer, user, phone, battery, thermal, client, failure
    }

    public struct LastEnd: Codable, Sendable, Equatable {
        public var reason: EndReason
        public var at: Date
        public init(reason: EndReason, at: Date) { self.reason = reason; self.at = at }
    }

    public enum Network: String, Codable, Sendable {
        case wifi, hotspot, wired, other, offline
    }

    public enum Thermal: String, Codable, Sendable {
        case nominal, fair, serious, critical
    }

    public struct Protection: Codable, Sendable, Equatable {
        public var stopAtPercent: Int?
        public var warnAtPercent: Int?
        public var stopOnThermal: Bool
        public var closedLidAllowed: Bool

        public init(stopAtPercent: Int? = nil, warnAtPercent: Int? = nil,
                    stopOnThermal: Bool = false, closedLidAllowed: Bool = false) {
            self.stopAtPercent = stopAtPercent
            self.warnAtPercent = warnAtPercent
            self.stopOnThermal = stopOnThermal
            self.closedLidAllowed = closedLidAllowed
        }
    }

    public var machineName: String
    public var readAt: Date
    public var battery: Battery?
    public var session: Session?
    public var lastEnd: LastEnd?
    public var network: Network
    public var lidClosed: Bool?
    public var thermal: Thermal
    public var protection: Protection

    public init(machineName: String, readAt: Date, battery: Battery? = nil, session: Session? = nil,
                lastEnd: LastEnd? = nil, network: Network = .other, lidClosed: Bool? = nil,
                thermal: Thermal = .nominal, protection: Protection = .init()) {
        self.machineName = machineName
        self.readAt = readAt
        self.battery = battery
        self.session = session
        self.lastEnd = lastEnd
        self.network = network
        self.lidClosed = lidClosed
        self.thermal = thermal
        self.protection = protection
    }

    /// On battery, whether the charge runs out before the session ends; an
    /// open-ended session always does.
    public static func batteryRunsOutFirst(minutesLeft: Int?, onAdapter: Bool, deadline: Date?, now: Date) -> Bool {
        guard !onAdapter, let minutesLeft else { return false }
        guard let deadline else { return true }
        return now.addingTimeInterval(TimeInterval(minutesLeft) * 60) < deadline
    }

    public var batteryRunsOutFirst: Bool {
        guard let battery, let session else { return false }
        return Self.batteryRunsOutFirst(minutesLeft: battery.minutesRemaining, onAdapter: battery.onAdapter,
                                        deadline: session.deadline, now: readAt)
    }
}
