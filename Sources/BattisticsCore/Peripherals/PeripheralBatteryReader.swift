import Foundation
import IOKit

public struct PeripheralBattery: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let percent: Int
    /// Which cell, for devices that report more than one: Left, Right, Case.
    /// nil when the device has a single battery and the name says it all.
    public let detail: String?

    public init(id: String, name: String, percent: Int, detail: String? = nil) {
        self.id = id
        self.name = name
        self.percent = percent
        self.detail = detail
    }
}

/// Battery levels for connected HID peripherals (Magic Keyboard, Mouse,
/// Trackpad and headphones that surface a BatteryPercent property).
/// Cheap single IORegistry scan; callers refresh only while visible.
public enum PeripheralBatteryReader {
    public static func read() -> [PeripheralBattery] {
        var results: [PeripheralBattery] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(service) }

            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }

            if let connected = property("Connected") as? Bool, !connected { continue }
            guard let percent = property("BatteryPercent") as? Int, (0...100).contains(percent) else {
                continue
            }
            let name = (property("Product") as? String) ?? "Unknown device"
            let identifier =
                (property("SerialNumber") as? String)
                ?? (property("DeviceAddress") as? String)
                ?? name
            results.append(PeripheralBattery(id: identifier, name: name, percent: percent))
        }
        return results.sorted { $0.name < $1.name }
    }
}
