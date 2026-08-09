import Foundation

public struct AdapterInfo: Sendable, Equatable {
    public let name: String?
    public let watts: Int?
    public let voltageMV: Int?
    public let amperageMA: Int?

    public init(name: String?, watts: Int?, voltageMV: Int?, amperageMA: Int?) {
        self.name = name
        self.watts = watts
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
    }
}

public enum HealthStatus: String, Sendable {
    case good
    case fair
    case poor

    public init(healthPercent: Double) {
        switch healthPercent {
        case 80...: self = .good
        case 60..<80: self = .fair
        default: self = .poor
        }
    }
}

public struct BatterySnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let batteryInstalled: Bool
    public let percent: Int
    public let rawCurrentCapacity: Int
    public let rawMaxCapacity: Int
    public let nominalCapacity: Int?
    public let designCapacity: Int
    public let cycleCount: Int
    public let designCycleCount: Int?
    public let temperatureC: Double?
    public let cellTemperatureC: Double?
    public let voltageMV: Int?
    public let amperageMA: Int?
    public let isCharging: Bool
    public let externalConnected: Bool
    public let fullyCharged: Bool
    public let avgTimeToEmptyMin: Int?
    public let avgTimeToFullMin: Int?
    public let systemTimeRemainingMin: Int?
    public let systemHealthStatus: String?
    public let serialNumber: String?
    public let deviceName: String?
    public let manufactureDate: Date?
    public let adapter: AdapterInfo?

    public init(
        timestamp: Date,
        batteryInstalled: Bool,
        percent: Int,
        rawCurrentCapacity: Int,
        rawMaxCapacity: Int,
        nominalCapacity: Int?,
        designCapacity: Int,
        cycleCount: Int,
        designCycleCount: Int?,
        temperatureC: Double?,
        cellTemperatureC: Double? = nil,
        voltageMV: Int?,
        amperageMA: Int?,
        isCharging: Bool,
        externalConnected: Bool,
        fullyCharged: Bool,
        avgTimeToEmptyMin: Int?,
        avgTimeToFullMin: Int?,
        systemTimeRemainingMin: Int?,
        systemHealthStatus: String?,
        serialNumber: String?,
        deviceName: String?,
        manufactureDate: Date?,
        adapter: AdapterInfo?
    ) {
        self.timestamp = timestamp
        self.batteryInstalled = batteryInstalled
        self.percent = percent
        self.rawCurrentCapacity = rawCurrentCapacity
        self.rawMaxCapacity = rawMaxCapacity
        self.nominalCapacity = nominalCapacity
        self.designCapacity = designCapacity
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.temperatureC = temperatureC
        self.cellTemperatureC = cellTemperatureC
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.fullyCharged = fullyCharged
        self.avgTimeToEmptyMin = avgTimeToEmptyMin
        self.avgTimeToFullMin = avgTimeToFullMin
        self.systemTimeRemainingMin = systemTimeRemainingMin
        self.systemHealthStatus = systemHealthStatus
        self.serialNumber = serialNumber
        self.deviceName = deviceName
        self.manufactureDate = manufactureDate
        self.adapter = adapter
    }

    /// The capacity the battery can currently hold. Prefers the controller's
    /// smoothed NominalChargeCapacity, the same value macOS bases its own
    /// health percentage on, so Battistics never contradicts System Settings.
    public var currentMaxCapacity: Int {
        nominalCapacity ?? rawMaxCapacity
    }

    public var healthPercent: Double {
        guard designCapacity > 0 else { return 0 }
        return Double(currentMaxCapacity) / Double(designCapacity) * 100
    }

    /// Health from the instantaneous measured full-charge capacity. More
    /// volatile than `healthPercent`; shown as a secondary stat.
    public var measuredHealthPercent: Double {
        guard designCapacity > 0 else { return 0 }
        return Double(rawMaxCapacity) / Double(designCapacity) * 100
    }

    public var healthStatus: HealthStatus {
        HealthStatus(healthPercent: healthPercent)
    }

    /// Signed instantaneous power. Negative while discharging, positive while charging.
    public var watts: Double? {
        guard let voltageMV, let amperageMA else { return nil }
        return Double(voltageMV) * Double(amperageMA) / 1_000_000
    }

    public var isDischarging: Bool {
        !externalConnected
    }

    /// Minutes to full while charging, minutes to empty on battery, nil when idle on AC.
    public var timeRemainingMin: Int? {
        if isCharging { return Self.validMinutes(avgTimeToFullMin) }
        if !externalConnected {
            return Self.validMinutes(avgTimeToEmptyMin) ?? Self.validMinutes(systemTimeRemainingMin)
        }
        return nil
    }

    /// The smart battery controller reports 65535 while the estimate is settling.
    static func validMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }
}
