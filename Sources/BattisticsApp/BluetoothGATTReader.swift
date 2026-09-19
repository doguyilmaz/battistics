import BattisticsCore
import CoreBluetooth
import Foundation
import Observation

/// Reads the standard Bluetooth Battery Service from connected devices.
///
/// This is the path macOS itself uses for peripherals it shows a level for.
/// Devices speaking HID over GATT are required by that profile to expose
/// service 0x180F, so a keyboard or mouse that publishes nothing through
/// IOKit or system_profiler may still answer here.
///
/// It is the app's only permission, and it is asked for exactly once, when
/// the user turns this on. Nothing here runs otherwise: `CBCentralManager`
/// is not even constructed until then, because constructing it is what
/// triggers the prompt.
@MainActor
@Observable
final class BluetoothGATTReader {
    enum State: Sendable, Equatable {
        case off
        case waiting
        /// macOS denied Bluetooth access, or Bluetooth is switched off.
        case denied
        case unavailable
        case ready
    }

    private(set) var state: State = .off
    private(set) var batteries: [PeripheralBattery] = []

    @ObservationIgnored private var session: GATTSession?
    @ObservationIgnored private var generation = UUID()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Prefs.readBluetoothBatteries) }
        set {
            UserDefaults.standard.set(newValue, forKey: Prefs.readBluetoothBatteries)
            newValue ? start() : stop()
        }
    }

    /// Called at launch. Does nothing unless the user already opted in, so an
    /// install that never touches this never sees a prompt.
    func startIfEnabled() {
        if isEnabled { start() }
    }

    func refresh() {
        session?.refresh()
    }

    private func start() {
        guard session == nil else { return refresh() }
        state = .waiting
        batteries = []
        let generation = UUID()
        self.generation = generation
        session = GATTSession(
            onState: { [weak self] state in
                Task { @MainActor in
                    guard self?.generation == generation else { return }
                    self?.state = state
                }
            },
            onBatteries: { [weak self] batteries in
                Task { @MainActor in
                    guard self?.generation == generation else { return }
                    self?.batteries = batteries
                }
            })
    }

    private func stop() {
        generation = UUID()
        session?.close()
        session = nil
        batteries = []
        state = .off
    }


}

/// Every CoreBluetooth interaction, kept off the main actor because the
/// delegate protocols are not isolated and its objects are not `Sendable`.
/// Constructed with `queue: nil`, so all callbacks land on the main queue —
/// `@unchecked Sendable` records that contract. Only plain values cross back.
private final class GATTSession: NSObject, @unchecked Sendable {
    /// Built per use: CBUUID is not Sendable, so a shared static of one is a
    /// concurrency error rather than a convenience.
    private static var batteryService: CBUUID { CBUUID(string: "180F") }
    private static var batteryLevel: CBUUID { CBUUID(string: "2A19") }

    private var central: CBCentralManager?
    private var connected: [UUID: CBPeripheral] = [:]
    private let onState: @Sendable (BluetoothGATTReader.State) -> Void
    private var levels: [UUID: PeripheralBattery] = [:]
    private let onBatteries: @Sendable ([PeripheralBattery]) -> Void

    init(
        onState: @escaping @Sendable (BluetoothGATTReader.State) -> Void,
        onBatteries: @escaping @Sendable ([PeripheralBattery]) -> Void
    ) {
        self.onState = onState
        self.onBatteries = onBatteries
        super.init()
        // Constructing this is what raises the permission prompt.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func refresh() {
        guard let central, central.state == .poweredOn else { return }
        let current = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let identifiers = Set(current.map(\.identifier))
        for identifier in Array(connected.keys) where !identifiers.contains(identifier) {
            if let peripheral = connected.removeValue(forKey: identifier) {
                peripheral.delegate = nil
                central.cancelPeripheralConnection(peripheral)
            }
            levels.removeValue(forKey: identifier)
        }
        publish()
        for peripheral in current {
            connected[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state == .connected {
                peripheral.discoverServices([Self.batteryService])
            } else if peripheral.state != .connecting {
                central.connect(peripheral, options: nil)
            }
        }
        onState(.ready)
    }

    private func publish() {
        onBatteries(levels.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) })
    }

    private func remove(_ peripheral: CBPeripheral) {
        connected.removeValue(forKey: peripheral.identifier)
        levels.removeValue(forKey: peripheral.identifier)
        publish()
    }

    func close() {
        for peripheral in connected.values {
            central?.cancelPeripheralConnection(peripheral)
        }
        connected.removeAll()
        levels.removeAll()
        publish()
        central?.delegate = nil
        central = nil
    }
}

extension GATTSession: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            for peripheral in connected.values { peripheral.delegate = nil }
            connected.removeAll()
            levels.removeAll()
            publish()
        }
        switch central.state {
        case .poweredOn: refresh()
        case .unauthorized: onState(.denied)
        case .unsupported, .poweredOff: onState(.unavailable)
        default: onState(.waiting)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        remove(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        remove(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard connected[peripheral.identifier] === peripheral else { return }
        peripheral.discoverServices([Self.batteryService])
    }
}

extension GATTSession: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, connected[peripheral.identifier] === peripheral else { return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        guard error == nil, connected[peripheral.identifier] === peripheral else { return }
        for characteristic in service.characteristics ?? [] {
            peripheral.readValue(for: characteristic)
            // Many devices push changes, which saves polling entirely.
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard error == nil, connected[peripheral.identifier] === peripheral,
            peripheral.state == .connected, characteristic.uuid == Self.batteryLevel,
            let value = characteristic.value?.first,
            (0...100).contains(Int(value)),
            let name = peripheral.name
        else { return }
        levels[peripheral.identifier] = PeripheralBattery(
            id: "gatt#\(peripheral.identifier)", name: name, percent: Int(value))
        publish()
    }
}
