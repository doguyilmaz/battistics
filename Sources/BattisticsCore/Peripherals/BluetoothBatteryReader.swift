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
    /// `system_profiler` is slow, about a second, so callers fetch on demand
    /// while a view is open rather than on a timer.
    public static func fetch() async -> [PeripheralBattery] {
        await Task.detached(priority: .utility) { () -> [PeripheralBattery] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return []
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(data)
        }.value
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

        // Keyed on the device and cell rather than the address: a device
        // reconnecting is briefly listed twice under two addresses, which
        // showed the same earpiece twice until macOS settled. It also keeps
        // a row's identity stable across a reconnect, so SwiftUI does not
        // tear the list down and rebuild it.
        var found: [String: PeripheralBattery] = [:]
        for entry in entries {
            guard let connected = entry["device_connected"] as? [[String: Any]] else { continue }
            for wrapper in connected {
                for (name, value) in wrapper {
                    guard let device = value as? [String: Any] else { continue }
                    for slot in slots {
                        guard let percent = percentage(device[slot.key]) else { continue }
                        let id = "\(name)#\(slot.label ?? "main")"
                        found[id] = PeripheralBattery(
                            id: id, name: name, percent: percent, detail: slot.label)
                    }
                }
            }
        }
        return found.values.sorted {
            ($0.name, $0.detail ?? "") < ($1.name, $1.detail ?? "")
        }
    }

    /// Values arrive as strings with the percent sign attached, and its side
    /// depends on the user's locale — "%100" in Turkish, "100%" in English.
    private static func percentage(_ value: Any?) -> Int? {
        guard let text = value as? String else { return value as? Int }
        let digits = text.filter(\.isNumber)
        guard let percent = Int(digits), (0...100).contains(percent) else { return nil }
        return percent
    }
}
