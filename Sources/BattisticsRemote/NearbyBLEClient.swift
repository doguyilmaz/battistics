#if os(iOS)
import CoreBluetooth
import Foundation

@MainActor
final class NearbyBLEClient: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    var onConnection: ((NearbyCredential, NearbyBLELink) -> Void)?
    private var manager: CBCentralManager?
    private var credentials: [NearbyCredential] = []
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var owners: [UUID: NearbyCredential] = [:]
    private var inputs: [UUID: CBCharacteristic] = [:]
    private var links: [UUID: NearbyBLELink] = [:]
    private var pending: [UUID: Data] = [:]
    private var writing: Set<UUID> = []
    private var retryAfter: [UUID: ContinuousClock.Instant] = [:]
    private var restoring: Set<UUID> = []

    func configure(_ credentials: [NearbyCredential]) {
        if self.credentials == credentials, manager != nil { reconnect(); return }
        self.credentials = credentials
        for id in Array(owners.keys) where !credentials.contains(owners[id]!) {
            close(id)
            owners[id] = nil
            peripherals[id] = nil
        }
        guard !credentials.isEmpty else { stop(); return }
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionRestoreIdentifierKey: "Battistics.nearby.central"])
        }
        scan()
        reconnect()
    }

    func stop() {
        manager?.stopScan()
        for id in Array(peripherals.keys) { close(id) }
        manager?.delegate = nil
        manager = nil
        peripherals = [:]
        owners = [:]
        restoring = []
    }

    func reconnect() {
        guard let manager, manager.state == .poweredOn else { return }
        for (id, peripheral) in peripherals where peripheral.state == .disconnected {
            guard !restoring.contains(id) else { continue }
            if retryAfter[id].map({ .now < $0 }) == true { continue }
            manager.connect(peripheral)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { restoreConnections(); scan(); reconnect() }
        else { for link in Array(links.values) { link.close() } }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        for peripheral in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            // Session keys belong to the old process. Reconnect to obtain a
            // fresh challenge instead of interpreting its encrypted stream.
            restoring.insert(peripheral.identifier)
        }
        restoreConnections()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripherals.count < 8 || peripherals[peripheral.identifier] != nil else { return }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard let credential = credentials.first(where: { services.contains(CBUUID(nsuuid: $0.serviceUUID)) }) else { return }
        peripherals[peripheral.identifier] = peripheral
        owners[peripheral.identifier] = credential
        peripheral.delegate = self
        if peripheral.state == .disconnected, retryAfter[peripheral.identifier].map({ .now >= $0 }) ?? true {
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { discover(peripheral); scan() }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { close(peripheral.identifier) }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let restored = restoring.remove(peripheral.identifier) != nil
        let automatic = links[peripheral.identifier] != nil || restored
        close(peripheral.identifier)
        // A pending Core Bluetooth connection can be restored when the Mac returns.
        if automatic, !credentials.isEmpty, central.state == .poweredOn { central.connect(peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { close(peripheral.identifier); return }
        guard let service = peripheral.services?.first(where: { service in
            credentials.contains { CBUUID(nsuuid: $0.serviceUUID) == service.uuid }
        }), let credential = credentials.first(where: { CBUUID(nsuuid: $0.serviceUUID) == service.uuid }) else {
            close(peripheral.identifier); return
        }
        owners[peripheral.identifier] = credential
        peripheral.discoverCharacteristics([NearbyBLE.input, NearbyBLE.output], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let input = service.characteristics?.first(where: { $0.uuid == NearbyBLE.input }),
              let output = service.characteristics?.first(where: { $0.uuid == NearbyBLE.output }) else {
            close(peripheral.identifier); return
        }
        inputs[peripheral.identifier] = input
        makeLink(peripheral)
        peripheral.setNotifyValue(true, for: output)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == NearbyBLE.output, characteristic.isNotifying else {
            close(peripheral.identifier); return
        }
    }

    private func makeLink(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard let credential = owners[id] else { close(id); return }
        guard links[id] == nil else { return }
        let link = NearbyBLELink(id: id, send: { [weak self] data in
            guard let self, self.inputs[id] != nil else { throw NearbyError.unavailable }
            guard (self.pending[id]?.count ?? 0) + data.count <= NearbyBLE.maximumQueuedBytes else { throw NearbyError.capacity }
            self.pending[id, default: Data()].append(data)
            self.drain(id)
        }, close: { [weak self] in self?.close(id) })
        links[id] = link
        onConnection?(credential, link)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == NearbyBLE.output, let data = characteristic.value else {
            close(peripheral.identifier); return
        }
        links[peripheral.identifier]?.received(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writing.remove(peripheral.identifier)
        if error != nil { close(peripheral.identifier) } else { drain(peripheral.identifier) }
    }

    private func scan() {
        guard manager?.state == .poweredOn, !credentials.isEmpty else { return }
        let missing = credentials.filter { credential in
            !peripherals.contains { id, peripheral in owners[id] == credential && peripheral.state != .disconnected }
        }
        if missing.isEmpty { manager?.stopScan() }
        else { manager?.scanForPeripherals(withServices: missing.map { CBUUID(nsuuid: $0.serviceUUID) }) }
    }

    private func discover(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(credentials.map { CBUUID(nsuuid: $0.serviceUUID) })
    }

    private func restoreConnections() {
        // Restoration precedes the manager's state callback on a cold launch.
        guard let manager, manager.state == .poweredOn else { return }
        for id in Array(restoring) {
            guard let peripheral = peripherals[id] else { restoring.remove(id); continue }
            if peripheral.state == .disconnected {
                restoring.remove(id)
                manager.connect(peripheral)
            } else { manager.cancelPeripheralConnection(peripheral) }
        }
    }

    private func drain(_ id: UUID) {
        guard !writing.contains(id), let peripheral = peripherals[id], let input = inputs[id],
              let bytes = pending[id], !bytes.isEmpty else { return }
        let chunk = Data(bytes.prefix(peripheral.maximumWriteValueLength(for: .withResponse)))
        guard !chunk.isEmpty else { close(id); return }
        pending[id] = Data(bytes.dropFirst(chunk.count))
        writing.insert(id)
        peripheral.writeValue(chunk, for: input, type: .withResponse)
    }

    private func close(_ id: UUID) {
        let link = links.removeValue(forKey: id)
        inputs[id] = nil
        pending[id] = nil
        writing.remove(id)
        retryAfter[id] = .now.advanced(by: .seconds(30))
        link?.close()
        if let peripheral = peripherals[id], peripheral.state != .disconnected { manager?.cancelPeripheralConnection(peripheral) }
    }
}
#endif
