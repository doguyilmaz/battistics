import Foundation

/// How macOS is configured to apply Low Power Mode. The system stores two
/// independent per-source flags; System Settings presents them as this one
/// four-way choice, so Battistics does too.
public enum LowPowerModeSetting: String, Sendable, Equatable {
    case never
    case always
    case onlyOnBattery
    case onlyOnPowerAdapter
}

/// MacBook Pro / Max only. Absent on every other Mac.
public enum EnergyMode: Int, Sendable, Equatable {
    case automatic = 0
    case low = 1
    case high = 2
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
