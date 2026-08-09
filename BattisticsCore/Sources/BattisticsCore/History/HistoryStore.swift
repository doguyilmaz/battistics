import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum HistoryError: Error {
    case cannotOpen(String)
    case statementFailed(String)
    case importFailed(String)
}

/// SQLite-backed history. An actor so all database work stays off the main
/// thread. Charge samples are written on power events only; power samples
/// arrive from a single coalesced background tick.
public actor HistoryStore {
    /// Owns the sqlite handle so it closes when the store goes away.
    /// Only ever touched by this actor; the class exists because an actor's
    /// nonisolated deinit cannot access non-Sendable stored properties.
    private final class Connection: @unchecked Sendable {
        let handle: OpaquePointer

        init(handle: OpaquePointer) { self.handle = handle }
        deinit { sqlite3_close_v2(handle) }
    }

    private let databaseURL: URL
    private var connection: Connection?
    private var db: OpaquePointer? { connection?.handle }

    public init(directory: URL) {
        databaseURL = directory.appendingPathComponent("history.sqlite")
    }

    // MARK: - Recording

    public func recordChargeSample(_ sample: ChargeSample) {
        guard ensureOpen() else { return }
        run(
            "INSERT OR IGNORE INTO charge_samples (ts, percent, external, charging) VALUES (?,?,?,?)",
            bind: [
                .int(Int64(sample.date.timeIntervalSince1970)),
                .int(Int64(sample.percent)),
                .int(sample.externalConnected ? 1 : 0),
                .int(sample.isCharging ? 1 : 0),
            ]
        )
    }

    public func recordPowerSample(date: Date, watts: Double, volts: Double?, amps: Double?, temperatureC: Double?) {
        guard ensureOpen() else { return }
        run(
            "INSERT OR IGNORE INTO power_samples (ts, watts, volts, amps, temp_c) VALUES (?,?,?,?,?)",
            bind: [
                .int(Int64(date.timeIntervalSince1970)),
                .real(watts),
                volts.map(SQLiteValue.real) ?? .null,
                amps.map(SQLiteValue.real) ?? .null,
                temperatureC.map(SQLiteValue.real) ?? .null,
            ]
        )
    }

    /// Records at most one health snapshot per calendar day.
    /// Returns the previous day's health percent when one exists so the
    /// caller can detect drops.
    @discardableResult
    public func recordHealthSnapshot(
        date: Date,
        healthPercent: Double,
        rawMaxCapacity: Int,
        nominalCapacity: Int?,
        designCapacity: Int,
        cycleCount: Int
    ) -> Double? {
        guard ensureOpen() else { return nil }
        let day = Self.dayKey(for: date)
        var previous: Double?
        query(
            "SELECT health_pct FROM health_snapshots WHERE day < ? ORDER BY day DESC LIMIT 1",
            bind: [.text(day)]
        ) { statement in
            previous = sqlite3_column_double(statement, 0)
        }
        run(
            """
            INSERT INTO health_snapshots (day, ts, health_pct, raw_max, nominal, design, cycles)
            VALUES (?,?,?,?,?,?,?)
            ON CONFLICT(day) DO UPDATE SET
              ts = excluded.ts, health_pct = excluded.health_pct, raw_max = excluded.raw_max,
              nominal = excluded.nominal, design = excluded.design, cycles = excluded.cycles
            """,
            bind: [
                .text(day),
                .int(Int64(date.timeIntervalSince1970)),
                .real(healthPercent),
                .int(Int64(rawMaxCapacity)),
                nominalCapacity.map { SQLiteValue.int(Int64($0)) } ?? .null,
                .int(Int64(designCapacity)),
                .int(Int64(cycleCount)),
            ]
        )
        return previous
    }

    public func hasHealthSnapshot(forDay date: Date) -> Bool {
        guard ensureOpen() else { return false }
        var found = false
        query(
            "SELECT 1 FROM health_snapshots WHERE day = ? LIMIT 1",
            bind: [.text(Self.dayKey(for: date))]
        ) { _ in found = true }
        return found
    }

    // MARK: - Series queries

    public func chargeSeries(from: Date, to: Date, bucketSeconds: Int) -> [SeriesPoint] {
        bucketedSeries(
            table: "charge_samples", column: "percent",
            from: from, to: to, bucketSeconds: bucketSeconds
        )
    }

    public func powerSeries(from: Date, to: Date, bucketSeconds: Int) -> [SeriesPoint] {
        guard ensureOpen() else { return [] }
        var points: [SeriesPoint] = []
        let bucket = Int64(max(bucketSeconds, 1))
        query(
            """
            SELECT (bucket_ts / ?1) * ?1 AS bucket, AVG(value) FROM (
              SELECT ts AS bucket_ts, ABS(watts) AS value FROM power_samples WHERE ts BETWEEN ?2 AND ?3
              UNION ALL
              SELECT hour_ts AS bucket_ts, avg_watts AS value FROM power_hourly WHERE hour_ts BETWEEN ?2 AND ?3
            ) GROUP BY bucket ORDER BY bucket
            """,
            bind: [
                .int(bucket),
                .int(Int64(from.timeIntervalSince1970)),
                .int(Int64(to.timeIntervalSince1970)),
            ]
        ) { statement in
            points.append(
                SeriesPoint(
                    date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0))),
                    value: sqlite3_column_double(statement, 1)
                ))
        }
        return points
    }

    public func temperatureSeries(from: Date, to: Date, bucketSeconds: Int) -> [SeriesPoint] {
        guard ensureOpen() else { return [] }
        var points: [SeriesPoint] = []
        let bucket = Int64(max(bucketSeconds, 1))
        query(
            """
            SELECT (bucket_ts / ?1) * ?1 AS bucket, AVG(value) FROM (
              SELECT ts AS bucket_ts, temp_c AS value FROM power_samples
                WHERE ts BETWEEN ?2 AND ?3 AND temp_c IS NOT NULL
              UNION ALL
              SELECT hour_ts AS bucket_ts, avg_temp AS value FROM power_hourly
                WHERE hour_ts BETWEEN ?2 AND ?3 AND avg_temp IS NOT NULL
            ) GROUP BY bucket ORDER BY bucket
            """,
            bind: [
                .int(bucket),
                .int(Int64(from.timeIntervalSince1970)),
                .int(Int64(to.timeIntervalSince1970)),
            ]
        ) { statement in
            points.append(
                SeriesPoint(
                    date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0))),
                    value: sqlite3_column_double(statement, 1)
                ))
        }
        return points
    }

    public func healthSeries() -> [HealthPoint] {
        guard ensureOpen() else { return [] }
        var points: [HealthPoint] = []
        query("SELECT ts, health_pct, raw_max, cycles FROM health_snapshots ORDER BY ts") { statement in
            points.append(
                HealthPoint(
                    date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0))),
                    healthPercent: sqlite3_column_double(statement, 1),
                    rawMaxCapacity: Int(sqlite3_column_int64(statement, 2)),
                    cycleCount: Int(sqlite3_column_int64(statement, 3))
                ))
        }
        return points
    }

    public func chargeSamples(from: Date, to: Date) -> [ChargeSample] {
        guard ensureOpen() else { return [] }
        var samples: [ChargeSample] = []
        query(
            "SELECT ts, percent, external, charging FROM charge_samples WHERE ts BETWEEN ? AND ? ORDER BY ts",
            bind: [.int(Int64(from.timeIntervalSince1970)), .int(Int64(to.timeIntervalSince1970))]
        ) { statement in
            samples.append(
                ChargeSample(
                    date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0))),
                    percent: Int(sqlite3_column_int64(statement, 1)),
                    externalConnected: sqlite3_column_int64(statement, 2) != 0,
                    isCharging: sqlite3_column_int64(statement, 3) != 0
                ))
        }
        return samples
    }

    public func timeTotals(from: Date, to: Date) -> TimeTotals {
        HistoryMath.timeTotals(samples: chargeSamples(from: from, to: to))
    }

    /// The moment the machine last switched from AC to battery, if it is
    /// currently on battery according to the recorded samples.
    public func lastUnplugDate() -> Date? {
        guard ensureOpen() else { return nil }
        var lastPluggedTs: Int64?
        var latestTs: Int64?
        var latestExternal = true
        query("SELECT ts, external FROM charge_samples ORDER BY ts DESC LIMIT 1") { statement in
            latestTs = sqlite3_column_int64(statement, 0)
            latestExternal = sqlite3_column_int64(statement, 1) != 0
        }
        guard latestTs != nil, !latestExternal else { return nil }
        query("SELECT MAX(ts) FROM charge_samples WHERE external = 1") { statement in
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                lastPluggedTs = sqlite3_column_int64(statement, 0)
            }
        }
        guard let lastPluggedTs else { return nil }
        var firstOnBattery: Int64?
        query(
            "SELECT MIN(ts) FROM charge_samples WHERE external = 0 AND ts > ?",
            bind: [.int(lastPluggedTs)]
        ) { statement in
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                firstOnBattery = sqlite3_column_int64(statement, 0)
            }
        }
        return firstOnBattery.map { Date(timeIntervalSince1970: Double($0)) }
    }

    // MARK: - Retention

    /// Raw power samples older than 30 days collapse into hourly averages;
    /// charge samples are kept 400 days. Health snapshots are kept forever.
    public func runRetention(now: Date = Date()) {
        guard ensureOpen() else { return }
        let powerCutoff = Int64(now.timeIntervalSince1970 - 30 * 24 * 3600)
        let chargeCutoff = Int64(now.timeIntervalSince1970 - 400 * 24 * 3600)
        run(
            """
            INSERT INTO power_hourly (hour_ts, avg_watts, max_watts, avg_temp)
            SELECT (ts / 3600) * 3600, AVG(ABS(watts)), MAX(ABS(watts)), AVG(temp_c)
            FROM power_samples WHERE ts < ?1
            GROUP BY (ts / 3600) * 3600
            ON CONFLICT(hour_ts) DO NOTHING
            """,
            bind: [.int(powerCutoff)]
        )
        run("DELETE FROM power_samples WHERE ts < ?", bind: [.int(powerCutoff)])
        run("DELETE FROM charge_samples WHERE ts < ?", bind: [.int(chargeCutoff)])
    }

    public func deleteAllHistory() {
        guard ensureOpen() else { return }
        run("DELETE FROM charge_samples")
        run("DELETE FROM power_samples")
        run("DELETE FROM power_hourly")
        run("DELETE FROM health_snapshots")
        run("VACUUM")
    }

    public func databaseSizeBytes() -> Int64 {
        let values = try? databaseURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - CSV

    public func exportCSV() -> String {
        guard ensureOpen() else { return CSVPort.header }
        var lines = [CSVPort.header]
        query("SELECT ts, percent, external, charging FROM charge_samples ORDER BY ts") { statement in
            lines.append(
                "charge,\(sqlite3_column_int64(statement, 0)),\(sqlite3_column_int64(statement, 1)),"
                    + "\(sqlite3_column_int64(statement, 2)),\(sqlite3_column_int64(statement, 3))")
        }
        query("SELECT ts, watts, volts, amps, temp_c FROM power_samples ORDER BY ts") { statement in
            let volts = sqlite3_column_type(statement, 2) == SQLITE_NULL ? "" : "\(sqlite3_column_double(statement, 2))"
            let amps = sqlite3_column_type(statement, 3) == SQLITE_NULL ? "" : "\(sqlite3_column_double(statement, 3))"
            let temp = sqlite3_column_type(statement, 4) == SQLITE_NULL ? "" : "\(sqlite3_column_double(statement, 4))"
            lines.append(
                "power,\(sqlite3_column_int64(statement, 0)),\(sqlite3_column_double(statement, 1)),\(volts),\(amps),\(temp)")
        }
        query("SELECT day, ts, health_pct, raw_max, nominal, design, cycles FROM health_snapshots ORDER BY day") { statement in
            let day = String(cString: sqlite3_column_text(statement, 0))
            let nominal = sqlite3_column_type(statement, 4) == SQLITE_NULL ? "" : "\(sqlite3_column_int64(statement, 4))"
            lines.append(
                "health,\(day),\(sqlite3_column_int64(statement, 1)),\(sqlite3_column_double(statement, 2)),"
                    + "\(sqlite3_column_int64(statement, 3)),\(nominal),\(sqlite3_column_int64(statement, 5)),"
                    + "\(sqlite3_column_int64(statement, 6))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Imports a Battistics CSV export. Duplicate rows are ignored.
    /// Returns the number of imported rows.
    @discardableResult
    public func importCSV(_ text: String) throws -> Int {
        guard ensureOpen() else { throw HistoryError.cannotOpen(databaseURL.path) }
        let parsed = try CSVPort.parse(text)
        run("BEGIN TRANSACTION")
        defer { run("COMMIT") }
        for sample in parsed.chargeSamples {
            recordChargeSample(sample)
        }
        for row in parsed.powerRows {
            run(
                "INSERT OR IGNORE INTO power_samples (ts, watts, volts, amps, temp_c) VALUES (?,?,?,?,?)",
                bind: [
                    .int(row.ts), .real(row.watts),
                    row.volts.map(SQLiteValue.real) ?? .null,
                    row.amps.map(SQLiteValue.real) ?? .null,
                    row.tempC.map(SQLiteValue.real) ?? .null,
                ]
            )
        }
        for row in parsed.healthRows {
            run(
                """
                INSERT INTO health_snapshots (day, ts, health_pct, raw_max, nominal, design, cycles)
                VALUES (?,?,?,?,?,?,?)
                ON CONFLICT(day) DO NOTHING
                """,
                bind: [
                    .text(row.day), .int(row.ts), .real(row.healthPercent), .int(row.rawMax),
                    row.nominal.map(SQLiteValue.int) ?? .null, .int(row.design), .int(row.cycles),
                ]
            )
        }
        return parsed.chargeSamples.count + parsed.powerRows.count + parsed.healthRows.count
    }

    // MARK: - SQLite plumbing

    private enum SQLiteValue {
        case int(Int64)
        case real(Double)
        case text(String)
        case null
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func ensureOpen() -> Bool {
        if connection != nil { return true }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var handle: OpaquePointer?
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
                return false
            }
            connection = Connection(handle: handle)
            run("PRAGMA journal_mode=WAL")
            run("PRAGMA synchronous=NORMAL")
            createSchema()
            return true
        } catch {
            return false
        }
    }

    private func createSchema() {
        run(
            """
            CREATE TABLE IF NOT EXISTS charge_samples (
              ts INTEGER PRIMARY KEY,
              percent INTEGER NOT NULL,
              external INTEGER NOT NULL,
              charging INTEGER NOT NULL
            ) WITHOUT ROWID
            """)
        run(
            """
            CREATE TABLE IF NOT EXISTS power_samples (
              ts INTEGER PRIMARY KEY,
              watts REAL NOT NULL,
              volts REAL,
              amps REAL,
              temp_c REAL
            ) WITHOUT ROWID
            """)
        run(
            """
            CREATE TABLE IF NOT EXISTS power_hourly (
              hour_ts INTEGER PRIMARY KEY,
              avg_watts REAL NOT NULL,
              max_watts REAL NOT NULL,
              avg_temp REAL
            ) WITHOUT ROWID
            """)
        run(
            """
            CREATE TABLE IF NOT EXISTS health_snapshots (
              day TEXT PRIMARY KEY,
              ts INTEGER NOT NULL,
              health_pct REAL NOT NULL,
              raw_max INTEGER NOT NULL,
              nominal INTEGER,
              design INTEGER NOT NULL,
              cycles INTEGER NOT NULL
            ) WITHOUT ROWID
            """)
    }

    private func bucketedSeries(table: String, column: String, from: Date, to: Date, bucketSeconds: Int) -> [SeriesPoint] {
        guard ensureOpen() else { return [] }
        var points: [SeriesPoint] = []
        let bucket = Int64(max(bucketSeconds, 1))
        query(
            "SELECT (ts / ?1) * ?1 AS bucket, AVG(\(column)) FROM \(table) WHERE ts BETWEEN ?2 AND ?3 GROUP BY bucket ORDER BY bucket",
            bind: [
                .int(bucket),
                .int(Int64(from.timeIntervalSince1970)),
                .int(Int64(to.timeIntervalSince1970)),
            ]
        ) { statement in
            points.append(
                SeriesPoint(
                    date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0))),
                    value: sqlite3_column_double(statement, 1)
                ))
        }
        return points
    }

    private func run(_ sql: String, bind values: [SQLiteValue] = []) {
        guard let db else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindValues(values, to: statement)
        sqlite3_step(statement)
    }

    private func query(_ sql: String, bind values: [SQLiteValue] = [], row: (OpaquePointer?) -> Void) {
        guard let db else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindValues(values, to: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }

    private func bindValues(_ values: [SQLiteValue], to statement: OpaquePointer?) {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let number): sqlite3_bind_int64(statement, position, number)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            case .text(let string): sqlite3_bind_text(statement, position, string, -1, sqliteTransient)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
    }
}
