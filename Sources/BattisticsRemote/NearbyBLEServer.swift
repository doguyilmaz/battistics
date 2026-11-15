#if os(macOS)
import CoreBluetooth
import Foundation

@MainActor
final class NearbyBLEServer: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    var onConnection: ((NearbyBLELink) -> Void)?
    private var manager: CBPeripheralManager?
    private var credential: NearbyCredential?
    private var output: CBMutableCharacteristic?
    private var links: [UUID: NearbyBLELink] = [:]
    private var centrals: [UUID: CBCentral] = [:]
    private var pending: [UUID: Data] = [:]
    private var serviceReady = false

    func start(_ credential: NearbyCredential) {
        stop()
        self.credential = credential
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func stop() {
        for link in Array(links.values) { link.close() }
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager?.delegate = nil
        manager = nil
        output = nil
        credential = nil
        serviceReady = false
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral === manager else { return }
        guard peripheral.state == .poweredOn, let credential else {
            for link in Array(links.values) { link.close() }
            return
        }
        peripheral.removeAllServices()
        serviceReady = false
        let input = CBMutableCharacteristic(type: NearbyBLE.input, properties: [.write], value: nil, permissions: [.writeable])
        let output = CBMutableCharacteristic(type: NearbyBLE.output, properties: [.notify], value: nil, permissions: [.readable])
        self.output = output
        let service = CBMutableService(type: CBUUID(nsuuid: credential.serviceUUID), primary: true)
        service.characteristics = [input, output]
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard peripheral === manager, error == nil, let credential else { return }
        serviceReady = true
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(nsuuid: credential.serviceUUID)]])
    }

    func ensureAdvertising() {
        guard let manager, manager.state == .poweredOn, !manager.isAdvertising, let credential else { return }
        if serviceReady { manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(nsuuid: credential.serviceUUID)]]) }
        else { peripheralManagerDidUpdateState(manager) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == NearbyBLE.output, links.count < 8, links[central.identifier] == nil else { return }
        centrals[central.identifier] = central
        let id = central.identifier
        let link = NearbyBLELink(id: id, send: { [weak self] data in
            guard let self, self.centrals[id] != nil else { throw NearbyError.unavailable }
            guard (self.pending[id]?.count ?? 0) + data.count <= NearbyBLE.maximumQueuedBytes else { throw NearbyError.capacity }
            self.pending[id, default: Data()].append(data)
            self.drain(id)
        }, close: { [weak self] in
            self?.links[id] = nil
            self?.centrals[id] = nil
            self?.pending[id] = nil
        })
        links[id] = link
        onConnection?(link)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        links[central.identifier]?.close()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == NearbyBLE.input, request.offset == 0,
                  let value = request.value, let link = links[request.central.identifier] else {
                peripheral.respond(to: request, withResult: .writeNotPermitted)
                continue
            }
            link.received(value)
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        for id in Array(pending.keys) { drain(id) }
    }

    private func drain(_ id: UUID) {
        guard let manager, let central = centrals[id], let output else { return }
        while let bytes = pending[id], !bytes.isEmpty {
            let chunk = Data(bytes.prefix(central.maximumUpdateValueLength))
            guard !chunk.isEmpty, manager.updateValue(chunk, for: output, onSubscribedCentrals: [central]) else { return }
            pending[id] = Data(bytes.dropFirst(chunk.count))
        }
    }
}
#endif
