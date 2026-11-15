import Foundation

public extension NearbyBluetoothState {
    var label: String {
        switch self {
        case .notDetermined: String(localized: "Not requested")
        case .authorized: String(localized: "Allowed")
        case .checking: String(localized: "Checking Bluetooth…")
        case .available: String(localized: "Available")
        case .denied: String(localized: "Access denied")
        case .restricted: String(localized: "Restricted by the system")
        case .poweredOff: String(localized: "Bluetooth is off")
        case .unsupported: String(localized: "Bluetooth unavailable")
        }
    }
}
