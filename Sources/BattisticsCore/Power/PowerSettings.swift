import Foundation

/// How macOS is configured to apply Low Power Mode. The system stores two
/// independent per-source flags; System Settings presents them as this one
/// four-way choice, so Battistics does too.
public enum LowPowerModeSetting: String, Sendable, Equatable, CaseIterable {
    case never
    case always
    case onlyOnBattery
    case onlyOnPowerAdapter
}

/// MacBook Pro / Max only. Absent on every other Mac.
public enum EnergyMode: Int, Sendable, Equatable, CaseIterable {
    case automatic = 0
    case low = 1
    case high = 2
}

/// Which idle timer. The raw value is the `pmset` key it sets.
public enum SleepTimer: String, Sendable, Equatable, CaseIterable {
    case display = "displaysleep"
    case system = "sleep"
    case disk = "disksleep"
}

/// Which power source a setting applies to, as `pmset` flags.
public enum PowerSource: String, Sendable, Equatable, CaseIterable {
    case battery = "-b"
    case ac = "-c"
    case all = "-a"
}

/// The discrete stops System Settings offers, rather than free-form minutes.
///
/// This is a security boundary, not a convenience. An arbitrary `Int` is not
/// a closed set: a negative one stringifies to `-1`, which `pmset` would read
/// as an option rather than a value. Restricting to enumerated cases keeps
/// every argument a bare non-negative token, so nothing crossing the boundary
/// can change the *shape* of the command.
public enum SleepInterval: Int, Sendable, Equatable, CaseIterable {
    case never = 0
    case oneMinute = 1
    case twoMinutes = 2
    case threeMinutes = 3
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case threeHours = 180
}

public struct PowerSettings: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public var lowPowerMode: Bool?
        public var systemSleepMinutes: Int?
        public var displaySleepMinutes: Int?
        public var diskSleepMinutes: Int?
        public var powerNap: Bool?
        public var wakeOnNetwork: Bool?
        public var sleepOnPowerButton: Bool?
        public var energyMode: EnergyMode?

        public init() {}
    }

    public var ac: Source?
    public var battery: Source?

    public init(ac: Source? = nil, battery: Source? = nil) {
        self.ac = ac
        self.battery = battery
    }

    /// nil on a Mac with no battery, where the four-way choice has no meaning.
    public var lowPowerMode: LowPowerModeSetting? {
        guard let onBattery = battery?.lowPowerMode, let onAC = ac?.lowPowerMode else {
            return nil
        }
        switch (onBattery, onAC) {
        case (false, false): return .never
        case (true, true): return .always
        case (true, false): return .onlyOnBattery
        case (false, true): return .onlyOnPowerAdapter
        }
    }

    /// Energy Mode is one system-wide setting; either source reports it.
    public var energyMode: EnergyMode? {
        ac?.energyMode ?? battery?.energyMode
    }
}

/// Reads macOS's power configuration.
///
/// The IOKit preferences API (`IOPMCopyPMPreferences` and friends) is not in
/// the public SDK — only assertions are — so this shells out to `pmset -g
/// custom`, which needs no privileges and costs about 9ms. Reading is cheap
/// enough to do on demand; nothing here polls.
public enum PowerSettingsReader {
    public static func fetch() async -> PowerSettings? {
        await Task.detached(priority: .utility) { () -> PowerSettings? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "custom"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return nil
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parse(String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Pure and unit-testable.
    ///
    /// Output is a section per power source, then indented `key   value`
    /// lines. Keys can contain spaces ("Sleep On Power Button"), so the value
    /// is the last whitespace-separated token and the key is everything else.
    public static func parse(_ text: String) -> PowerSettings {
        var settings = PowerSettings()
        var current: WritableKeyPath<PowerSettings, PowerSettings.Source?>?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasSuffix(":") {
                switch line.dropLast().lowercased() {
                case "ac power": current = \.ac
                case "battery power": current = \.battery
                default: current = nil
                }
                if let current, settings[keyPath: current] == nil {
                    settings[keyPath: current] = PowerSettings.Source()
                }
                continue
            }

            guard let path = current,
                let separator = line.lastIndex(where: \.isWhitespace)
            else { continue }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
            var source = settings[keyPath: path] ?? PowerSettings.Source()
            apply(key: key, value: value, to: &source)
            settings[keyPath: path] = source
        }
        return settings
    }

    private static func apply(key: String, value: String, to source: inout PowerSettings.Source) {
        let number = Int(value)
        let flag = number.map { $0 != 0 }
        switch key.lowercased() {
        case "lowpowermode": source.lowPowerMode = flag
        case "sleep": source.systemSleepMinutes = number
        case "displaysleep": source.displaySleepMinutes = number
        case "disksleep": source.diskSleepMinutes = number
        case "powernap": source.powerNap = flag
        case "womp": source.wakeOnNetwork = flag
        case "sleep on power button": source.sleepOnPowerButton = flag
        case "powermode": source.energyMode = number.flatMap(EnergyMode.init(rawValue:))
        default: break
        }
    }
}

/// Builds the `pmset` invocations that change power settings.
///
/// Separate from running them: every argument here comes from a fixed enum
/// case, so the command can be assembled and tested without a shell, a
/// password prompt, or root anywhere near it.
public enum PowerSettingsWriter {
    public static let executable = "/usr/bin/pmset"

    /// `-b` is battery, `-c` is the power adapter. macOS stores Low Power
    /// Mode as one flag per source, so the four-way choice sets both.
    public static func arguments(for setting: LowPowerModeSetting) -> [String] {
        let (battery, ac): (String, String) =
            switch setting {
            case .never: ("0", "0")
            case .always: ("1", "1")
            case .onlyOnBattery: ("1", "0")
            case .onlyOnPowerAdapter: ("0", "1")
            }
        return ["-b", "lowpowermode", battery, "-c", "lowpowermode", ac]
    }

    /// Energy Mode is system-wide, so `-a`.
    public static func arguments(for mode: EnergyMode) -> [String] {
        ["-a", "powermode", String(mode.rawValue)]
    }

    public static func arguments(
        for timer: SleepTimer, interval: SleepInterval, source: PowerSource
    ) -> [String] {
        [source.rawValue, timer.rawValue, String(interval.rawValue)]
    }

    public static func command(_ arguments: [String]) -> String {
        ([executable] + arguments).joined(separator: " ")
    }
}
