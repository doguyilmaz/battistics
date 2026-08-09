import Foundation

/// One-file CSV format. Every data line starts with its table name so a
/// single export holds the full history and stays trivially greppable:
///   charge,<unix ts>,<percent>,<external 0|1>,<charging 0|1>
///   power,<unix ts>,<watts>,<volts?>,<amps?>,<temp_c?>
///   hourly,<hour ts>,<avg watts>,<max watts>,<avg temp?>
///   health,<yyyy-mm-dd>,<unix ts>,<health pct>,<raw max>,<nominal?>,<design>,<cycles>
public enum CSVPort {
    public static let header = "# Battistics history export v1"

    /// Sanity window for imported unix timestamps (through year 2100);
    /// also prevents Int64 -> Date -> Int64 round-trip overflow traps.
    static let timestampRange: ClosedRange<Int64> = 0...4_102_444_800

    public struct PowerRow: Sendable, Equatable {
        public let ts: Int64
        public let watts: Double
        public let volts: Double?
        public let amps: Double?
        public let tempC: Double?

        public init(ts: Int64, watts: Double, volts: Double?, amps: Double?, tempC: Double?) {
            self.ts = ts
            self.watts = watts
            self.volts = volts
            self.amps = amps
            self.tempC = tempC
        }
    }

    public struct HealthRow: Sendable, Equatable {
        public let day: String
        public let ts: Int64
        public let healthPercent: Double
        public let rawMax: Int64
        public let nominal: Int64?
        public let design: Int64
        public let cycles: Int64

        public init(day: String, ts: Int64, healthPercent: Double, rawMax: Int64, nominal: Int64?, design: Int64, cycles: Int64) {
            self.day = day
            self.ts = ts
            self.healthPercent = healthPercent
            self.rawMax = rawMax
            self.nominal = nominal
            self.design = design
            self.cycles = cycles
        }
    }

    public struct HourlyRow: Sendable, Equatable {
        public let hourTs: Int64
        public let avgWatts: Double
        public let maxWatts: Double
        public let avgTemp: Double?

        public init(hourTs: Int64, avgWatts: Double, maxWatts: Double, avgTemp: Double?) {
            self.hourTs = hourTs
            self.avgWatts = avgWatts
            self.maxWatts = maxWatts
            self.avgTemp = avgTemp
        }
    }

    public struct Parsed: Sendable {
        public var chargeSamples: [ChargeSample] = []
        public var powerRows: [PowerRow] = []
        public var hourlyRows: [HourlyRow] = []
        public var healthRows: [HealthRow] = []

        public init() {}

        public var rowCount: Int {
            chargeSamples.count + powerRows.count + hourlyRows.count + healthRows.count
        }
    }

    public static func parse(_ text: String) throws -> Parsed {
        var parsed = Parsed()
        // isNewline splits CRLF correctly; "\r\n" is a single Character in
        // Swift, so splitting on "\n" would not split those files at all.
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            switch fields.first {
            case "charge":
                guard fields.count == 5,
                    let ts = timestamp(fields[1]), let percent = Int(fields[2]),
                    let external = Int(fields[3]), let charging = Int(fields[4])
                else { throw HistoryError.importFailed("Bad charge row: \(line)") }
                parsed.chargeSamples.append(
                    ChargeSample(
                        date: Date(timeIntervalSince1970: Double(ts)),
                        percent: percent,
                        externalConnected: external != 0,
                        isCharging: charging != 0
                    ))
            case "power":
                guard fields.count == 6, let ts = timestamp(fields[1]), let watts = Double(fields[2])
                else { throw HistoryError.importFailed("Bad power row: \(line)") }
                parsed.powerRows.append(
                    PowerRow(
                        ts: ts, watts: watts,
                        volts: Double(fields[3]), amps: Double(fields[4]), tempC: Double(fields[5])
                    ))
            case "hourly":
                guard fields.count == 5,
                    let ts = timestamp(fields[1]), let avg = Double(fields[2]),
                    let max = Double(fields[3])
                else { throw HistoryError.importFailed("Bad hourly row: \(line)") }
                parsed.hourlyRows.append(
                    HourlyRow(hourTs: ts, avgWatts: avg, maxWatts: max, avgTemp: Double(fields[4])))
            case "health":
                guard fields.count == 8,
                    let ts = timestamp(fields[2]), let health = Double(fields[3]),
                    let rawMax = Int64(fields[4]), let design = Int64(fields[6]),
                    let cycles = Int64(fields[7])
                else { throw HistoryError.importFailed("Bad health row: \(line)") }
                parsed.healthRows.append(
                    HealthRow(
                        day: fields[1], ts: ts, healthPercent: health, rawMax: rawMax,
                        nominal: Int64(fields[5]), design: design, cycles: cycles
                    ))
            default:
                throw HistoryError.importFailed("Unknown row type: \(line)")
            }
        }
        return parsed
    }

    private static func timestamp(_ field: String) -> Int64? {
        guard let value = Int64(field), timestampRange.contains(value) else { return nil }
        return value
    }
}
