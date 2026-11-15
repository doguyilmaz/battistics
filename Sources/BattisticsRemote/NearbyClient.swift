#if os(iOS)
import CoreBluetooth
import Foundation
import Network

@MainActor
public final class NearbyClient {
    public var onStatus: ((String, RemoteStatus) -> Void)?
    private let browser = NearbyLANBrowser()
    private let bluetooth = NearbyBLEClient()
    private var credentials: [NearbyCredential] = []
    private var peers: [UUID: NearbyPeer] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var retryAfter: [String: ContinuousClock.Instant] = [:]
    private var foreground = false
    private var ticker: Task<Void, Never>?

    public init() {
        browser.onEndpoints = { [weak self] endpoints in self?.endpoints = endpoints; self?.connectLAN() }
        bluetooth.onConnection = { [weak self] credential, link in self?.adopt(link, credential: credential) }
    }

    public func configure(_ credentials: [NearbyCredential]) {
        self.credentials = credentials.filter(\.isValid).sorted { $0.macID < $1.macID }
        for peer in Array(peers.values) where !credentials.contains(peer.credential) { peer.close() }
        if foreground, !credentials.isEmpty { browser.start(); connectLAN() }
        else { browser.stop() }
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted { bluetooth.stop() }
        else if foreground || CBCentralManager.authorization == .allowedAlways { bluetooth.configure(self.credentials) }
    }

    public func setForeground(_ foreground: Bool) {
        self.foreground = foreground
        ticker?.cancel()
        ticker = nil
        configure(credentials)
        if foreground {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    if self?.credentials.isEmpty == false { self?.browser.start() }
                    if let self { for peer in Array(self.peers.values) where !peer.healthy { peer.close() } }
                    self?.connectLAN()
                    self?.bluetooth.reconnect()
                }
            }
        } else {
            for peer in Array(peers.values) where peer.link.kind == .lan { peer.close() }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        credentials = []
        for peer in Array(peers.values) { peer.close() }
        browser.stop()
        bluetooth.stop()
        endpoints = [:]
        retryAfter = [:]
    }

    public func hasFreshConnection(to macID: String) -> Bool {
        peers.values.contains { $0.credential.macID == macID && $0.healthy }
    }

    public func routes(to macID: String) -> [RemoteRoute] {
        [RemoteRoute.Kind.lan, .bluetooth].compactMap { kind in
            guard let peer = peers.values.first(where: { $0.credential.macID == macID && $0.link.kind == kind && $0.healthy }) else { return nil }
            return RemoteRoute(kind: kind) { request, deadline in try await peer.request(request, until: deadline) }
        }
    }

    private func connectLAN() {
        guard foreground else { return }
        for credential in credentials {
            if peers.values.contains(where: { $0.credential == credential && $0.link.kind == .lan }) { continue }
            if retryAfter[credential.macID].map({ .now < $0 }) == true { continue }
            guard let endpoint = endpoints[credential.discoveryID] else { continue }
            let link = NearbyLANLink(connection: NWConnection(to: endpoint, using: NearbyTLS.parameters(credential)))
            adopt(link, credential: credential)
            link.start()
        }
    }

    private func adopt(_ link: any NearbyLink, credential: NearbyCredential) {
        guard credentials.contains(credential), peers.count < 16 else { link.close(); return }
        let peer = NearbyPeer(link: link, credential: credential, server: false)
        peers[link.id] = peer
        peer.onClosed = { [weak self] in
            self?.peers[link.id] = nil
            if link.kind == .lan { self?.retryAfter[credential.macID] = .now.advanced(by: .seconds(30)) }
        }
        peer.onMessage = { [weak self, weak peer] message in
            if case .status(_, let status) = message {
                guard status.nearbyProtocol == 1, status.nearbyID == credential.discoveryID else { peer?.close(); return }
                self?.onStatus?(credential.macID, status)
            }
            else if case .ready = message {} else { peer?.close() }
        }
    }
}
#endif
