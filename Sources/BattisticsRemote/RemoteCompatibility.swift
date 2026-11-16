import Foundation

public enum RemoteCompatibility {
    public static let minimumMac = "1.6.0"
    public static let minimumPhone = "1.1.0"

    public static func message(peer: RemoteAppInfo?, name: String, appName: String, localAppName: String, local: RemoteAppInfo?, minimum: String) -> String {
        guard let peer else { return String(localized: "\(name) has not shared its \(appName) version. Open an updated copy on that device.") }
        if peer.needsUpdate(for: minimum) == true {
            return String(localized: "Update \(appName) on \(name) to \(minimum) or later for nearby connections.")
        }
        if let local, local.needsUpdate(for: peer.minimumPeerVersion) == true {
            return String(localized: "Nearby connections with \(name) require \(localAppName) \(peer.minimumPeerVersion) or later on this device.")
        }
        if peer.needsUpdate(for: minimum) == nil {
            return String(localized: "This version could not be checked. Update the app on that device.")
        }
        return String(localized: "App versions support nearby connections. Bluetooth and Local Network permissions are checked separately.")
    }
}
