import CoreBluetooth
import Foundation

@MainActor
enum NearbyBLE {
    static let input = CBUUID(string: "3D64BE88-681B-43DD-B51A-5AC953E65C01")
    static let output = CBUUID(string: "3D64BE88-681B-43DD-B51A-5AC953E65C02")
    static let maximumQueuedBytes = 512 * 1024
}
