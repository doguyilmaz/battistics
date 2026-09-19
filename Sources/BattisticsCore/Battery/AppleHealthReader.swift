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
/// it is read via a relatively expensive system_profiler report. Callers
/// fetch once per launch and cache the result.
public enum AppleHealthReader {
    public static func fetch() async -> AppleHealthInfo? {
        guard let data = try? await BoundedCommand.run(
            executable: "/usr/sbin/system_profiler", arguments: ["SPPowerDataType", "-json"],
            timeout: 15, maximumOutputBytes: 2_097_152
        ), !Task.isCancelled else { return nil }
        return parse(data)
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
