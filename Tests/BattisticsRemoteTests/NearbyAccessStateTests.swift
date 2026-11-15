import CoreBluetooth
import Network
import Testing
@testable import BattisticsRemote

@Suite("Nearby permission reporting")
struct NearbyAccessStateTests {
    @Test func permissionTakesPrecedenceOverRadioState() {
        #expect(NearbyBluetoothState.resolve(authorization: .denied, state: .poweredOn) == .denied)
        #expect(NearbyBluetoothState.resolve(authorization: .restricted, state: .poweredOff) == .restricted)
        #expect(NearbyBluetoothState.resolve(authorization: .notDetermined, state: nil) == .notDetermined)
    }

    @Test func allowedAccessDistinguishesTheRadioFromAConnection() {
        #expect(NearbyBluetoothState.resolve(authorization: .allowedAlways, state: nil) == .authorized)
        #expect(NearbyBluetoothState.resolve(authorization: .allowedAlways, state: .poweredOff) == .poweredOff)
        #expect(NearbyBluetoothState.resolve(authorization: .allowedAlways, state: .poweredOn) == .available)
        #expect(NearbyBluetoothState.resolve(authorization: .allowedAlways, state: .unsupported) == .unsupported)
        #expect(NearbyBluetoothState.resolve(authorization: .allowedAlways, state: .resetting) == .checking)
    }

    @Test func aBonjourPolicyDenialCanDirectTheUserToSettings() {
        #expect(NearbyLocalNetworkState.failure(.dns(-65570)) == .denied)
    }

    @Test func ordinaryDiscoveryFailuresDoNotClaimPermissionWasDenied() {
        #expect(NearbyLocalNetworkState.failure(.dns(-65563)) == .unavailable)
        #expect(NearbyLocalNetworkState.failure(.posix(.ENETDOWN)) == .unavailable)
    }
}
