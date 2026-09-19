import Foundation

public struct AppleHealthInfo: Sendable, Equatable {
    public let maximumCapacityPercent: Int?
    public let condition: String?

    public init(maximumCapacityPercent: Int?, condition: String?) {
        self.maximumCapacityPercent = maximumCapacityPercent
        self.condition = condition
    }
}

/// macOS's own battery health verdict, the "Maximum Capacity" shown in
/// System Settings and the System Report. It comes from powerd's long-term
/// smoothed model and is not derivable from the live controller values, so
/// it is read via system_profiler. That costs about a second of background
/// CPU; callers fetch once per launch and cache.
public enum AppleHealthReader {
    public static func fetch() async -> AppleHealthInfo? {
        await Task.detached(priority: .utility) { () -> AppleHealthInfo? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPPowerDataType", "-json"]
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
            return parse(data)
        }.value
    }

    /// Pure and unit-testable.
    public static func parse(_ data: Data) -> AppleHealthInfo? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["SPPowerDataType"] as? [[String: Any]]
        else { return nil }
        for entry in entries {
            guard let health = entry["sppower_battery_health_info"] as? [String: Any] else {
                continue
            }
            let capacity: Int?
            if let text = health["sppower_battery_health_maximum_capacity"] as? String {
                capacity = Int(text.filter(\.isNumber))
            } else {
                capacity = health["sppower_battery_health_maximum_capacity"] as? Int
            }
            let condition = health["sppower_battery_health"] as? String
            return AppleHealthInfo(maximumCapacityPercent: capacity.flatMap { (1...100).contains($0) ? $0 : nil }, condition: condition)
        }
        return nil
    }
}
