import CoreBluetooth

/// Permission and radio state, independent of whether a trusted peer is nearby.
public enum NearbyBluetoothState: Sendable {
    case notDetermined, authorized, checking, available, denied, restricted, poweredOff, unsupported

    public static func current(_ state: CBManagerState? = nil) -> Self {
        resolve(authorization: CBManager.authorization, state: state)
    }

    static func resolve(authorization: CBManagerAuthorization, state: CBManagerState?) -> Self {
        switch authorization {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .allowedAlways: break
        @unknown default: return .restricted
        }
        switch state {
        case nil: return .authorized
        case .poweredOn: return .available
        case .poweredOff: return .poweredOff
        case .unsupported: return .unsupported
        case .unauthorized: return .denied
        default: return .checking
        }
    }
}
