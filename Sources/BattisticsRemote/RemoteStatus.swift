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
        /// Instantaneous measured full-charge capacity in mAh.
        public var rawMaxCapacityMah: Int?
        /// Original factory design capacity in mAh.
        public var designCapacityMah: Int?
        /// Battery pack voltage in millivolts.
        public var voltageMV: Int?
        /// Signed battery current in milliamps.
        public var amperageMA: Int?
        /// Connected power adapter name/description.
        public var adapterName: String?
        /// Adapter voltage in millivolts.
        public var adapterVoltageMV: Int?
        /// Adapter current rating in milliamps.
        public var adapterAmperageMA: Int?
        /// Battery pack manufacture date when available.
        public var manufactureDate: Date?
        /// Battery pack serial number when available.
        public var serialNumber: String?

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
            rawMaxCapacityMah: Int? = nil,
            designCapacityMah: Int? = nil,
            voltageMV: Int? = nil,
            amperageMA: Int? = nil,
            adapterName: String? = nil,
            adapterVoltageMV: Int? = nil,
            adapterAmperageMA: Int? = nil,
            manufactureDate: Date? = nil,
            serialNumber: String? = nil
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
            self.rawMaxCapacityMah = rawMaxCapacityMah
            self.designCapacityMah = designCapacityMah
            self.voltageMV = voltageMV
            self.amperageMA = amperageMA
            self.adapterName = adapterName
            self.adapterVoltageMV = adapterVoltageMV
            self.adapterAmperageMA = adapterAmperageMA
            self.manufactureDate = manufactureDate
            self.serialNumber = serialNumber
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

    public struct CommandResult: Codable, Sendable, Equatable {
        public var id: String
        public var failure: RemoteFailure?
        public init(id: String, failure: RemoteFailure?) { self.id = id; self.failure = failure }
    }

    /// The Mac writes at least this often while it is awake and sharing.
    public static let heartbeat: TimeInterval = 600

    /// Whether this reading is recent enough to call the Mac reachable.
    public func isFresh(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(readAt) < Self.heartbeat * 2
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
        pairedPhoneName: String? = nil
    ) {
        self.machineName = machineName
        self.macModel = macModel
        self.osVersion = osVersion
        self.pairedPhoneName = pairedPhoneName
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
