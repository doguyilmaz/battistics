import Foundation

/// Battery levels macOS publishes for connected Bluetooth devices.
///
/// Separate from `PeripheralBatteryReader`, which reads the IORegistry class
/// Apple uses for its own Magic Keyboard, Mouse and Trackpad. Everything else
/// — AirPods and other earpieces — only appears here.
///
/// Most Bluetooth devices report nothing at all. Logitech's MX line, for one,
/// carries its battery over a proprietary HID++ protocol rather than
/// publishing it to macOS, which is why even the system's own Bluetooth UI
/// cannot show it.
public enum BluetoothBatteryReader {
    /// A relatively expensive system report, fetched only by the visible
    /// peripherals pane. Cancellation stops an obsolete report in flight.
    public static func fetch() async -> [PeripheralBattery] {
        guard let data = try? await BoundedCommand.run(
            executable: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"],
            timeout: 15, maximumOutputBytes: 2_097_152
        ), !Task.isCancelled else { return [] }
        return parse(data)
    }

    /// Pure and unit-testable.
    ///
    /// Only `device_connected` is read: a disconnected device keeps the level
    /// it had when it left, and showing that as current would be a lie.
    public static func parse(_ data: Data) -> [PeripheralBattery] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        // An earpiece reports several batteries; a plain device reports one,
        // and that one needs no sub-label.
        let slots: [(key: String, label: String?)] = [
            ("device_batteryLevelMain", nil),
            ("device_batteryLevelLeft", "Left"),
            ("device_batteryLevelRight", "Right"),
            ("device_batteryLevelCase", "Case"),
        ]

        // Display names are not identities: two devices can have the same
        // factory name. Keep each physical address and battery cell separate.
        var found: [String: PeripheralBattery] = [:]
        for entry in entries {
            guard let connected = entry["device_connected"] as? [[String: Any]] else { continue }
            for wrapper in connected {
                for (name, value) in wrapper {
                    guard let device = value as? [String: Any] else { continue }
                    let address = (device["device_address"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "-", with: ":")
                        .lowercased()
                    let identity = address.flatMap { $0.isEmpty ? nil : $0 } ?? "name:\(name)"
                    for slot in slots {
                        guard let percent = percentage(device[slot.key]) else { continue }
                        let id = "\(identity)#\(slot.label ?? "main")"
                        found[id] = PeripheralBattery(
                            id: id, name: name, percent: percent, detail: slot.label)
                    }
                }
            }
        }
        return found.values.sorted {
            ($0.name, $0.detail ?? "", $0.id) < ($1.name, $1.detail ?? "", $1.id)
        }
    }

    /// Values arrive as strings with the percent sign attached, and its side
    /// depends on the user's locale — "%100" in Turkish, "100%" in English.
    private static func percentage(_ value: Any?) -> Int? {
        guard let text = value as? String else {
            guard let percent = value as? Int, (0...100).contains(percent) else { return nil }
            return percent
        }
        let digits = text.filter(\.isNumber)
        guard let percent = Int(digits), (0...100).contains(percent) else { return nil }
        return percent
    }
}
