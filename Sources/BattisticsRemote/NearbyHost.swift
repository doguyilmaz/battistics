#if os(macOS)
import Foundation
import os

@MainActor
public final class NearbyHost {
    private let lan = NearbyLANServer()
    private let bluetooth = NearbyBLEServer()
    private var credential: NearbyCredential?
    private var peers: [UUID: NearbyPeer] = [:]
    private var inFlight: [UUID: Int] = [:]
    private var ticker: Task<Void, Never>?
    private var read: (() async throws -> RemoteStatus)?
    private var command: ((RemoteRequest) async throws -> RemoteStatus)?
    private var delivered: ((String) async -> Void)?
    private var awaitingDelivery: [UUID: (peer: UUID, command: String)] = [:]
    private static let logger = Logger(subsystem: "com.doguyilmaz.Battistics.Remote", category: "Nearby")

    public init() {}

    public func start(_ credential: NearbyCredential,
                      read: @escaping () async throws -> RemoteStatus,
                      command: @escaping (RemoteRequest) async throws -> RemoteStatus,
                      delivered: @escaping (String) async -> Void) {
        guard self.credential != credential else { return }
        stop()
        guard credential.isValid else { return }
        self.credential = credential
        self.read = read
        self.command = command
        self.delivered = delivered
        lan.onConnection = { [weak self] link in self?.accept(link) }
        bluetooth.onConnection = { [weak self] link in self?.accept(link) }
        do { try lan.start(credential) }
        catch { Self.logger.error("LAN listener could not start; code \((error as NSError).code)") }
        bluetooth.start(credential)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self else { return }
                if self.lan.listener == nil, let credential = self.credential { try? self.lan.start(credential) }
                self.bluetooth.ensureAdvertising()
                // Keep notifications flowing after a delayed phone wake. Only
                // sending to "healthy" peers would strand an idle BLE session.
                let connected = self.peers.values.filter { $0.authenticated }
                guard !connected.isEmpty, let status = try? await self.read?() else { continue }
                for peer in connected { try? peer.send(.status(id: UUID(), status: status)) }
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        for peer in Array(peers.values) { peer.close() }
        lan.stop()
        bluetooth.stop()
        credential = nil
        read = nil
        command = nil
        delivered = nil
        awaitingDelivery = [:]
    }

    private func accept(_ link: any NearbyLink) {
        guard let credential, peers.count < 8 else { link.close(); return }
        let peer = NearbyPeer(link: link, credential: credential, server: true)
        peers[link.id] = peer
        peer.onClosed = { [weak self] in
            self?.peers[link.id] = nil
            self?.inFlight[link.id] = nil
            self?.awaitingDelivery = self?.awaitingDelivery.filter { $0.value.peer != link.id } ?? [:]
        }
        peer.onReady = { [weak self, weak peer] in
            Task { @MainActor in
                guard let self, let peer, let status = try? await self.read?() else { return }
                try? peer.send(.status(id: UUID(), status: status))
            }
        }
        peer.onMessage = { [weak self, weak peer] message in
            guard let self, let peer else { return }
            guard (self.inFlight[link.id] ?? 0) < 4 else { peer.close(); return }
            self.inFlight[link.id, default: 0] += 1
            Task { @MainActor in
                defer { if let count = self.inFlight[link.id] { self.inFlight[link.id] = count - 1 } }
                do {
                    switch message {
                    case .read(let id):
                        if let status = try await self.read?() { try peer.send(.status(id: id, status: status)) }
                    case .command(let id, let request):
                        guard self.awaitingDelivery.values.filter({ $0.peer == link.id }).count < 32 else {
                            throw NearbyError.capacity
                        }
                        if let status = try await self.command?(request) {
                            guard self.peers[link.id] === peer else { return }
                            self.awaitingDelivery[id] = (link.id, request.id)
                            try peer.send(.status(id: id, status: status))
                        }
                    case .acknowledged(let id):
                        if self.awaitingDelivery[id]?.peer == link.id,
                           let sent = self.awaitingDelivery.removeValue(forKey: id) { await self.delivered?(sent.command) }
                    default: throw NearbyError.malformedFrame
                    }
                } catch { peer.close() }
            }
        }
        if let link = link as? NearbyLANLink { link.onReady = { [weak peer] in peer?.begin() }; link.start() }
        else { peer.begin() }
    }
}
#endif
