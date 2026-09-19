import Foundation
import Testing

@testable import BattisticsCore

@Suite("Bluetooth battery parsing")
struct BluetoothBatteryTests {
    /// Trimmed from real `system_profiler SPBluetoothDataType -json` output.
    private let sample = """
        {"SPBluetoothDataType": [{
          "controller_properties": {"controller_address": "5C:E9:1E:AF:63:13"},
          "device_connected": [
            {"MX Master 3S": {
              "device_address": "D1:9F:8F:F9:EC:62",
              "device_minorType": "Mouse",
              "device_services": "0x400000 < BLE >"}},
            {"Dogu’s AirPods Pro": {
              "device_address": "AA:BB:CC:DD:EE:FF",
              "device_minorType": "Headphones",
              "device_batteryLevelCase": "%100",
              "device_batteryLevelLeft": "%95",
              "device_batteryLevelRight": "%90"}},
            {"Solo Buds": {
              "device_address": "11:22:33:44:55:66",
              "device_batteryLevelMain": "%42"}}
          ],
          "device_not_connected": [
            {"Old Headphones": {"device_batteryLevelMain": "%50"}}
          ]}]}
        """.data(using: .utf8)!

    @Test func readsEveryBatteryAnEarpieceReports() {
        let found = BluetoothBatteryReader.parse(sample)
        let airpods = found.filter { $0.name.contains("AirPods") }
        #expect(airpods.count == 3)
        #expect(airpods.contains { $0.detail == "Left" && $0.percent == 95 })
        #expect(airpods.contains { $0.detail == "Right" && $0.percent == 90 })
        #expect(airpods.contains { $0.detail == "Case" && $0.percent == 100 })
    }

    @Test func aSingleBatteryCarriesNoSubLabel() {
        let solo = BluetoothBatteryReader.parse(sample).first { $0.name == "Solo Buds" }
        #expect(solo?.percent == 42)
        #expect(solo?.detail == nil)
    }

    /// A device that reports no battery is not a device with 0%.
    @Test func devicesWithoutABatteryAreSkipped() {
        #expect(!BluetoothBatteryReader.parse(sample).contains { $0.name == "MX Master 3S" })
    }

    /// Disconnected devices report a stale level; showing it would be a lie.
    @Test func onlyConnectedDevicesCount() {
        #expect(!BluetoothBatteryReader.parse(sample).contains { $0.name == "Old Headphones" })
    }

    @Test func identifiersAreStableAndUniquePerBattery() {
        let ids = BluetoothBatteryReader.parse(sample).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func identicalNamesAtDifferentAddressesRemainDistinct() {
        let doubled = """
            {"SPBluetoothDataType": [{"device_connected": [
              {"Dogu’s AirPods Pro": {
                "device_address": "AA:BB:CC:DD:EE:FF",
                "device_batteryLevelCase": "%100"}},
              {"Dogu’s AirPods Pro": {
                "device_address": "11:22:33:44:55:66",
                "device_batteryLevelCase": "%95"}}
            ]}]}
            """.data(using: .utf8)!
        let found = BluetoothBatteryReader.parse(doubled)
        #expect(found.count == 2)
        #expect(Set(found.map(\.id)).count == 2)
        #expect(found.first?.detail == "Case")
    }

    @Test func repeatedPhysicalAddressIsReportedOnce() {
        let repeated = """
            {"SPBluetoothDataType": [{"device_connected": [
              {"Headphones": {"device_address": "AA:BB:CC:DD:EE:FF", "device_batteryLevelMain": "90%"}},
              {"Headphones": {"device_address": "aa-bb-cc-dd-ee-ff", "device_batteryLevelMain": "90%"}}
            ]}]}
            """.data(using: .utf8)!
        #expect(BluetoothBatteryReader.parse(repeated).count == 1)
    }

    @Test func garbageYieldsNothing() {
        #expect(BluetoothBatteryReader.parse(Data("nonsense".utf8)).isEmpty)
    }
}
