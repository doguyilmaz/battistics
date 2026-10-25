import Foundation

/// Everything the phone shows about one Mac, read on the Mac in one pass.
public struct RemoteStatus: Codable, Sendable, Equatable {
    /// How macOS is configured to apply Low Power Mode across battery and adapter.
    public enum LowPowerPolicy: String, Codable, Sendable, CaseIterable {
        case never
        case onlyOnBattery
        case onlyOnAdapter
        case always
    }

    public struct Battery: Codable, Sendable, Equatable {
        public var percent: Int
        public var isCharging: Bool
        public var onAdapter: Bool
        /// Minutes to empty on battery, to full while charging.
        public var minutesRemaining: Int?
        public var healthPercent: Int?
        /// Whether macOS Low Power Mode is currently active for the current power source.
        public var lowPowerMode: Bool?
        /// System-wide Low Power Mode policy (Never, Only on Battery, Only on Adapter, Always).
        public var lowPowerPolicy: LowPowerPolicy?
        /// Signed instantaneous power in watts (positive charging, negative discharging).
        public var watts: Double?
        /// Connected power adapter rating in watts (e.g. 67, 96, 140).
        public var adapterWatts: Int?
        /// Battery temperature in Celsius.
        public var temperatureC: Double?
        /// Battery cycle count.
        public var cycleCount: Int?
        /// Design cycle limit (typically 1000 on Mac notebooks).
        public var designCycleCount: Int?
        /// Current charge in mAh.
        public var currentCapacityMah: Int?
        /// Smoothed full-charge capacity in mAh.
        public var maxCapacityMah: Int?
        /// Original factory design capacity in mAh.
        public var designCapacityMah: Int?
        /// Battery pack voltage in millivolts.
        public var voltageMV: Int?
        /// Signed battery current in milliamps.
        public var amperageMA: Int?
        /// Connected power adapter name/description.
        public var adapterName: String?
        /// Battery pack manufacture date when available.
        public var manufactureDate: Date?

        public init(
            percent: Int,
            isCharging: Bool,
            onAdapter: Bool,
            minutesRemaining: Int? = nil,
            healthPercent: Int? = nil,
            lowPowerMode: Bool? = nil,
            lowPowerPolicy: LowPowerPolicy? = nil,
            watts: Double? = nil,
            adapterWatts: Int? = nil,
            temperatureC: Double? = nil,
            cycleCount: Int? = nil,
            designCycleCount: Int? = nil,
            currentCapacityMah: Int? = nil,
            maxCapacityMah: Int? = nil,
            designCapacityMah: Int? = nil,
            voltageMV: Int? = nil,
            amperageMA: Int? = nil,
            adapterName: String? = nil,
            manufactureDate: Date? = nil
        ) {
            self.percent = percent
            self.isCharging = isCharging
            self.onAdapter = onAdapter
            self.minutesRemaining = minutesRemaining
            self.healthPercent = healthPercent
            self.lowPowerMode = lowPowerMode
            self.lowPowerPolicy = lowPowerPolicy
            self.watts = watts
            self.adapterWatts = adapterWatts
            self.temperatureC = temperatureC
            self.cycleCount = cycleCount
            self.designCycleCount = designCycleCount
            self.currentCapacityMah = currentCapacityMah
            self.maxCapacityMah = maxCapacityMah
            self.designCapacityMah = designCapacityMah
            self.voltageMV = voltageMV
            self.amperageMA = amperageMA
            self.adapterName = adapterName
            self.manufactureDate = manufactureDate
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

        public var countdownRange: ClosedRange<Date>? {
            deadline.map { RemoteStatus.countdownRange(startedAt: startedAt, deadline: $0) }
        }

        /// False once a timed session's deadline passed, before the Mac reports it ended.
        public func isActive(at date: Date) -> Bool {
            deadline.map { $0 > date } ?? true
        }
    }

    /// The countdown's span, safe against a deadline earlier than the start.
    public static func countdownRange(startedAt: Date, deadline: Date) -> ClosedRange<Date> {
        min(startedAt, deadline)...deadline
    }

    public struct ChargePoint: Codable, Sendable, Equatable {
        public var at: Date
        public var percent: Double
        public init(at: Date, percent: Double) { self.at = at; self.percent = percent }
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
        public var closedLidAllowed: Bool

        public init(stopAtPercent: Int? = nil, warnAtPercent: Int? = nil, closedLidAllowed: Bool = false) {
            self.stopAtPercent = stopAtPercent
            self.warnAtPercent = warnAtPercent
            self.closedLidAllowed = closedLidAllowed
        }
    }

    /// Sampled on the Mac only when a phone asks, since measuring costs a few seconds of work.
    public struct Extras: Codable, Sendable, Equatable {
        public struct Accessory: Codable, Sendable, Equatable {
            public var name: String
            public var percent: Int
            /// Which cell for multi-battery devices: Left, Right, Case.
            public var detail: String?
            public init(name: String, percent: Int, detail: String? = nil) {
                self.name = name
                self.percent = percent
                self.detail = detail
            }
        }

        public struct App: Codable, Sendable, Equatable {
            public var name: String
            public var cpuPercent: Double
            /// Share of the energy the sampled apps used, 0...1, when macOS reports it.
            public var energyShare: Double?
            public init(name: String, cpuPercent: Double, energyShare: Double? = nil) {
                self.name = name
                self.cpuPercent = cpuPercent
                self.energyShare = energyShare
            }
        }

        public var sampledAt: Date
        public var accessories: [Accessory]
        public var apps: [App]

        public init(sampledAt: Date, accessories: [Accessory], apps: [App]) {
            self.sampledAt = sampledAt
            self.accessories = accessories
            self.apps = apps
        }
    }

    public var machineName: String
    /// Hardware marketing or model identifier for the Mac (e.g. "MacBook Pro (14-inch, M2 Pro)").
    public var macModel: String?
    /// macOS version string on the Mac (e.g. "macOS 15.4").
    public var osVersion: String?
    /// Known Personal Hotspot / paired iPhone name observed by the Mac when available.
    public var pairedPhoneName: String?
    public var readAt: Date
    public var battery: Battery?
    public var session: Session?
    public var lastEnd: LastEnd?
    public var network: Network
    /// Wi-Fi or Personal Hotspot SSID when available.
    public var networkName: String?
    public var lidClosed: Bool?
    public var thermal: Thermal
    public var protection: Protection
    /// The last 24 hours of charge, oldest first; nil when history is off.
    public var chargeHistory: [ChargePoint]?
    /// The outcome of the newest phone command the Mac handled.
    public var lastCommand: CommandResult?
    public var extras: Extras?
    /// Set by a Mac that posts its own alerts through iCloud, so a phone does
    /// not repeat the ones it pushes.
    public var pushesAlerts: Bool?

    public struct CommandResult: Codable, Sendable, Equatable {
        public var id: String
        public var failure: RemoteFailure?
        public init(id: String, failure: RemoteFailure?) { self.id = id; self.failure = failure }
    }

    /// The Mac writes at least this often while it is awake and sharing.
    public static let heartbeat: TimeInterval = 600

    /// During a Keep Awake session the Mac writes more often, so the phone can
    /// tell a silent Mac from a quiet one within minutes instead of a quarter hour.
    public static let sessionHeartbeat: TimeInterval = 120

    /// How long a phone that cannot fetch (a pending notification, a widget, a
    /// Live Activity) waits before saying it has not heard from the Mac. iOS
    /// throttles the silent pushes that wake the phone to a few per hour, so a
    /// shorter wait reports a healthy Mac as silent.
    public static let unheardDelay: TimeInterval = 30 * 60

    /// The write interval the Mac promised in this reading. Missing means a Mac
    /// build from before the field existed, which wrote every `heartbeat`.
    public var heartbeatSeconds: TimeInterval?

    public static func heartbeat(duringSession: Bool) -> TimeInterval {
        duringSession ? sessionHeartbeat : heartbeat
    }

    public var expectedHeartbeat: TimeInterval { heartbeatSeconds ?? Self.heartbeat }

    /// After this moment, a fetch that returns no newer reading means the Mac
    /// is unreachable. Only a real fetch may conclude that; see `unheardDate`.
    public var staleDate: Date {
        let missed: Double = session == nil ? 2 : 4
        return readAt.addingTimeInterval(expectedHeartbeat * missed)
    }

    /// When surfaces that cannot fetch stop presenting this reading as live.
    public var unheardDate: Date {
        max(staleDate, readAt.addingTimeInterval(Self.unheardDelay))
    }

    /// The earliest a phone that has heard nothing may mention it: just past
    /// the stale window.
    public var quietDelay: TimeInterval { staleDate.timeIntervalSince(readAt) + 45 }

    /// How long after `readAt` a phone that has heard nothing should warn.
    /// iOS throttles silent pushes by its own rules: while recent background
    /// deliveries arrive steadily the warning comes just past the stale
    /// window, and the longer the gaps, the longer it waits, up to
    /// `unheardDelay`, so a healthy Mac is not reported as silent.
    public func watchdogDelay(backgroundDeliveries: [Date], now: Date) -> TimeInterval {
        let minimum = quietDelay
        let maximum = max(minimum, Self.unheardDelay)
        let times = backgroundDeliveries.sorted() + [now]
        // A short burst says nothing about throttling, which iOS starts after a few pushes.
        guard times.count >= 4, let oldest = times.first,
              now.timeIntervalSince(oldest) >= Self.unheardDelay / 2 else { return maximum }
        let longestGap = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? maximum
        return min(maximum, max(minimum, longestGap * 1.5))
    }

    /// Whether this reading is recent enough to call the Mac reachable.
    public func isFresh(at now: Date = Date()) -> Bool {
        now < staleDate
    }

    public init(
        machineName: String,
        readAt: Date,
        battery: Battery? = nil,
        session: Session? = nil,
        lastEnd: LastEnd? = nil,
        network: Network = .other,
        networkName: String? = nil,
        lidClosed: Bool? = nil,
        thermal: Thermal = .nominal,
        protection: Protection = .init(),
        macModel: String? = nil,
        osVersion: String? = nil,
        pairedPhoneName: String? = nil,
        heartbeatSeconds: TimeInterval? = nil
    ) {
        self.machineName = machineName
        self.macModel = macModel
        self.osVersion = osVersion
        self.pairedPhoneName = pairedPhoneName
        self.heartbeatSeconds = heartbeatSeconds
        self.readAt = readAt
        self.battery = battery
        self.session = session
        self.lastEnd = lastEnd
        self.network = network
        self.networkName = networkName
        self.lidClosed = lidClosed
        self.thermal = thermal
        self.protection = protection
    }

    /// Personal Hotspot keeps a closed Mac online away from Wi‑Fi, and the Mac
    /// must allow closed-lid sessions from the phone.
    public var isBagReady: Bool {
        network == .hotspot && protection.closedLidAllowed
    }

    /// Whether this mode needs Personal Hotspot to stay online in a bag.
    public func needsHotspot(for mode: Mode) -> Bool {
        mode == .lidClosed && network != .hotspot
    }

    /// On battery, whether the charge runs out before the session ends; an
    /// open-ended session only warns when remaining battery time is under 2 hours.
    public static func batteryRunsOutFirst(minutesLeft: Int?, onAdapter: Bool, deadline: Date?, now: Date) -> Bool {
        guard !onAdapter, let minutesLeft else { return false }
        guard let deadline else { return minutesLeft < 120 }
        return now.addingTimeInterval(TimeInterval(minutesLeft) * 60) < deadline
    }

    public var batteryRunsOutFirst: Bool {
        guard let battery, let session else { return false }
        return Self.batteryRunsOutFirst(minutesLeft: battery.minutesRemaining, onAdapter: battery.onAdapter,
                                        deadline: session.deadline, now: readAt)
    }
}
