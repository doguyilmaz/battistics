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

public enum BatteryHealth {
    /// DesignCapacity is a nameplate minimum, not a measurement, so a young
    /// pack genuinely gauges above it and the reading drifts down while the
    /// controller relearns Qmax. macOS clamps its Maximum Capacity at 100%,
    /// and so does every Battistics surface, so the app never reports a
    /// figure System Settings will not show. The unclamped ratio survives in
    /// `measuredHealthPercent` and in the stored history.
    public static func display(_ rawPercent: Double) -> Double {
        min(rawPercent, 100)
    }

    /// The controller re-estimates NominalChargeCapacity continuously, so
    /// consecutive daily snapshots swing several points with no degradation
    /// behind them. Median rather than mean: a single re-learning spike
    /// should not drag the result at all.
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Trailing rolling median, same length as the input. The first entries
    /// average fewer than `window` samples, which is the honest thing to do
    /// at the start of a series rather than dropping or padding them.
    public static func rollingMedian(_ values: [Double], window: Int) -> [Double] {
        guard window > 1 else { return values }
        return values.indices.map { index in
            let start = max(0, index - window + 1)
            return median(Array(values[start...index])) ?? values[index]
        }
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
    /// True when the date was derived from the serial week code, which
    /// only carries week precision, not a calendar day.
    public let manufactureDateIsApproximate: Bool
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
        manufactureDateIsApproximate: Bool = false,
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
        self.manufactureDateIsApproximate = manufactureDateIsApproximate
        self.adapter = adapter
    }

    /// The capacity the battery can currently hold. Prefers the controller's
    /// smoothed NominalChargeCapacity, the same value macOS bases its own
    /// health percentage on, so Battistics never contradicts System Settings.
    public var currentMaxCapacity: Int {
        if let nominalCapacity, nominalCapacity > 0 { return nominalCapacity }
        return rawMaxCapacity
    }

    public var hasHealthReading: Bool { designCapacity > 0 && currentMaxCapacity > 0 }

    public var hasMeasuredHealthReading: Bool { designCapacity > 0 && rawMaxCapacity > 0 }

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

    public var displayHealthPercent: Double {
        BatteryHealth.display(healthPercent)
    }

    public var healthStatus: HealthStatus {
        HealthStatus(healthPercent: displayHealthPercent)
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
