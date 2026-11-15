#if os(iOS)
import CoreBluetooth
import Foundation

@MainActor
final class NearbyBLEClient: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    var onConnection: ((NearbyCredential, NearbyBLELink) -> Void)?
    var onState: ((NearbyBluetoothState) -> Void)?
    private var manager: CBCentralManager?
    private var credentials: [NearbyCredential] = []
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var owners: [UUID: NearbyCredential] = [:]
    private var inputs: [UUID: CBCharacteristic] = [:]
    private var links: [UUID: NearbyBLELink] = [:]
    private var pending: [UUID: Data] = [:]
    private var writing: Set<UUID> = []
    private var candidates = NearbyCandidates()
    private var reconnectAfterDisconnect: Set<UUID> = []
    private var closing: Set<UUID> = []
    private var setupDeadlines: [UUID: Task<Void, Never>] = [:]
    private var setupTokens: [UUID: UUID] = [:]
    private var stopping = false
    private var restoring: Set<UUID> = []
    private var rejectedRestorations: [CBPeripheral] = []

    func configure(_ credentials: [NearbyCredential]) {
        if self.credentials == credentials, manager != nil { reconnect(); return }
        self.credentials = credentials
        for id in Array(owners.keys) where !credentials.contains(owners[id]!) {
            close(id, reason: .rejected)
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
        stopping = true
        manager?.stopScan()
        if manager?.state == .poweredOn {
            for peripheral in rejectedRestorations { manager?.cancelPeripheralConnection(peripheral) }
        }
        rejectedRestorations = []
        for id in Array(peripherals.keys) { close(id, reason: .rejected) }
        manager?.delegate = nil
        manager = nil
        peripherals = [:]
        owners = [:]
        restoring = []
        reconnectAfterDisconnect = []
        candidates.clear()
        stopping = false
    }

    func reconnect() {
        guard let manager, manager.state == .poweredOn else { return }
        for (id, peripheral) in peripherals where peripheral.state == .disconnected {
            guard !restoring.contains(id) else { continue }
            manager.connect(peripheral)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === manager else { return }
        refreshState()
        if central.state == .poweredOn {
            for peripheral in rejectedRestorations { central.cancelPeripheralConnection(peripheral) }
            rejectedRestorations = []
            restoreConnections()
            scan()
            reconnect()
        }
        else { for link in Array(links.values) { link.close() } }
    }

    func refreshState() { onState?(.current(manager?.state)) }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard central === manager else { return }
        for peripheral in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
            guard candidates.admit(peripheral.identifier, macID: "restored.\(peripheral.identifier)") else {
                if central.state == .poweredOn { central.cancelPeripheralConnection(peripheral) }
                else { rejectedRestorations.append(peripheral) }
                continue
            }
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            // Session keys belong to the old process. Reconnect to obtain a
            // fresh challenge instead of interpreting its encrypted stream.
            restoring.insert(peripheral.identifier)
        }
        restoreConnections()
    }

    func centralManager(_ central: CBCentralManager, didDiscover discovered: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === manager else { return }
        // Keep the delegate/characteristics attached to the connected object;
        // an advertising callback is not a new connection or a new session.
        let peripheral = peripherals[discovered.identifier] ?? discovered
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard let credential = credentials.first(where: { services.contains(CBUUID(nsuuid: $0.serviceUUID)) }) else { return }
        guard candidates.admit(peripheral.identifier, macID: credential.macID) else { return }
        peripherals[peripheral.identifier] = peripheral
        owners[peripheral.identifier] = credential
        peripheral.delegate = self
        if peripheral.state == .disconnected {
            beginSetup(peripheral)
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === manager, peripherals[peripheral.identifier] === peripheral else {
            if central.state == .poweredOn, central !== manager || peripherals[peripheral.identifier] == nil {
                central.cancelPeripheralConnection(peripheral)
            }
            return
        }
        beginSetup(peripheral)
        discover(peripheral)
        scan()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === manager, peripherals[peripheral.identifier] === peripheral else { return }
        close(peripheral.identifier, reason: .setup)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === manager, peripherals[peripheral.identifier] === peripheral else { return }
        if reconnectAfterDisconnect.remove(peripheral.identifier) != nil {
            if central.state == .poweredOn { beginSetup(peripheral); central.connect(peripheral) }
            return
        }
        let restored = restoring.remove(peripheral.identifier) != nil
        let reason: NearbyCandidates.Failure = links[peripheral.identifier]?.authenticated == true ? .disconnected : .setup
        close(peripheral.identifier, reason: restored ? .setup : reason)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripherals[peripheral.identifier] === peripheral else { return }
        guard error == nil else { close(peripheral.identifier, reason: .setup); return }
        guard let service = peripheral.services?.first(where: { service in
            credentials.contains { CBUUID(nsuuid: $0.serviceUUID) == service.uuid }
        }), let credential = credentials.first(where: { CBUUID(nsuuid: $0.serviceUUID) == service.uuid }) else {
            close(peripheral.identifier); return
        }
        guard candidates.admit(peripheral.identifier, macID: credential.macID) else { close(peripheral.identifier); return }
        owners[peripheral.identifier] = credential
        peripheral.discoverCharacteristics([NearbyBLE.input, NearbyBLE.output], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripherals[peripheral.identifier] === peripheral else { return }
        guard error == nil,
              let input = service.characteristics?.first(where: { $0.uuid == NearbyBLE.input }),
              let output = service.characteristics?.first(where: { $0.uuid == NearbyBLE.output }) else {
            close(peripheral.identifier, reason: .setup); return
        }
        inputs[peripheral.identifier] = input
        makeLink(peripheral)
        peripheral.setNotifyValue(true, for: output)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripherals[peripheral.identifier] === peripheral else { return }
        guard error == nil, characteristic.uuid == NearbyBLE.output, characteristic.isNotifying else {
            close(peripheral.identifier, reason: .setup); return
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
        setupDeadlines.removeValue(forKey: id)?.cancel()
        setupTokens[id] = nil
        link.onAuthenticated = { [weak self] in self?.candidates.authenticate(id) }
        onConnection?(credential, link)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripherals[peripheral.identifier] === peripheral else { return }
        guard error == nil, characteristic.uuid == NearbyBLE.output, let data = characteristic.value else {
            close(peripheral.identifier); return
        }
        links[peripheral.identifier]?.received(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripherals[peripheral.identifier] === peripheral else { return }
        writing.remove(peripheral.identifier)
        if error != nil { close(peripheral.identifier) } else { drain(peripheral.identifier) }
    }

    private func scan() {
        guard !stopping, manager?.state == .poweredOn, !credentials.isEmpty else { return }
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
            beginSetup(peripheral)
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

    private func beginSetup(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier, token = UUID()
        setupDeadlines[id]?.cancel()
        setupTokens[id] = token
        setupDeadlines[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.setupTokens[id] == token else { return }
            self.close(id, reason: .rejected)
        }
    }

    private func close(_ id: UUID, reason: NearbyCandidates.Failure? = nil) {
        guard closing.insert(id).inserted else { return }
        defer { closing.remove(id) }
        let link = links.removeValue(forKey: id)
        let retry = candidates.failed(id, reason: reason ?? (link?.authenticated == true ? .disconnected : .rejected))
        setupDeadlines.removeValue(forKey: id)?.cancel()
        setupTokens[id] = nil
        inputs[id] = nil
        pending[id] = nil
        writing.remove(id)
        link?.close()
        if let peripheral = peripherals[id] {
            if !retry {
                peripherals[id] = nil
                owners[id] = nil
                restoring.remove(id)
                reconnectAfterDisconnect.remove(id)
                peripheral.delegate = nil
            }
            if peripheral.state != .disconnected {
                if retry { reconnectAfterDisconnect.insert(id) }
                manager?.cancelPeripheralConnection(peripheral)
            } else if retry, manager?.state == .poweredOn { beginSetup(peripheral); manager?.connect(peripheral) }
        }
        scan()
    }
}
#endif
