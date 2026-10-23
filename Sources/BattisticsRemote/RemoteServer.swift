import Foundation
import Network

/// Listens on exactly the given addresses, so binding it to the Tailscale
/// interface keeps it off the LAN and the internet. All state belongs to `queue`.
public final class RemoteServer: @unchecked Sendable {
    public typealias Handler = @MainActor @Sendable (RemoteRequest) async -> RemoteReply

    private let queue = DispatchQueue(label: "com.doguyilmaz.Battistics.remote.server")
    private let port: NWEndpoint.Port
    private let handler: Handler
    private var listeners: [String: NWListener] = [:]
    private var open: [String: Int] = [:]
    private var failures: [String: [Date]] = [:]
    private static let maximumConnections = 8
    private static let connectionsPerPeer = 2
    private static let failureLimit = 5
    private static let failureWindow: TimeInterval = 60

    public init(port: UInt16 = RemoteWire.defaultPort, handler: @escaping Handler) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
    }

    /// Replaces the listening addresses; returns the ones that are listening.
    @discardableResult
    public func listen(on hosts: Set<String>) async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async {
                for (host, listener) in self.listeners where !hosts.contains(host) {
                    listener.cancel()
                    self.listeners[host] = nil
                }
                let group = DispatchGroup()
                for host in hosts where self.listeners[host] == nil {
                    guard let listener = self.makeListener(host: host) else { continue }
                    self.listeners[host] = listener
                    group.enter()
                    let pending = Pending()
                    listener.stateUpdateHandler = { [weak self] state in
                        switch state {
                        case .ready:
                            pending.leave(group)
                        case .failed, .cancelled:
                            pending.leave(group)
                            listener.cancel()
                            if self?.listeners[host] === listener { self?.listeners[host] = nil }
                        default: break
                        }
                    }
                    listener.start(queue: self.queue)
                }
                group.notify(queue: self.queue) { continuation.resume(returning: Set(self.listeners.keys)) }
            }
        }
    }

    public func stop() async { await listen(on: []) }

    private func makeListener(host: String) -> NWListener? {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .init(host), port: port)
        guard let listener = try? NWListener(using: parameters) else { return nil }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return listener
    }

    private func accept(_ connection: NWConnection) {
        let peer = Self.peerHost(connection)
        // A packet for the Tailscale address can still arrive on another
        // interface; only tailnet and local peers get as far as the parser.
        guard Self.isAllowedPeer(peer), open.values.reduce(0, +) < Self.maximumConnections,
              open[peer, default: 0] < Self.connectionsPerPeer else { connection.cancel(); return }
        open[peer, default: 0] += 1
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed: connection.cancel()
            case .cancelled:
                guard let self else { return }
                self.open[peer, default: 1] -= 1
                if self.open[peer] == 0 { self.open[peer] = nil }
            default: break
            }
        }
        connection.start(queue: queue)
        let exchange = Exchange()
        queue.asyncAfter(deadline: .now() + 3) { if !exchange.received { connection.cancel() } }
        queue.asyncAfter(deadline: .now() + 30) { connection.cancel() }
        if isRateLimited(peer) {
            reply(.init(.rateLimited, "Too many failed attempts. Try again in a minute."), on: connection)
            return
        }
        read(connection, peer: peer, buffer: Data(), exchange: exchange)
    }

    /// A request line has to arrive quickly; answering may take longer.
    private final class Exchange: @unchecked Sendable {
        var received = false
    }

    static func isAllowedPeer(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "::1" || TailscaleAddress.contains(host)
    }

    private func read(_ connection: NWConnection, peer: String, buffer: Data, exchange: Exchange) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: RemoteWire.maximumBytes) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.contains(10) {
                exchange.received = true
                guard let request = try? RemoteWire.decode(RemoteRequest.self, from: buffer) else {
                    self.reply(.init(.invalidRequest, "The request could not be read."), on: connection)
                    return
                }
                Task {
                    let reply = await self.handler(request)
                    self.queue.async {
                        if reply.error?.code == .unauthorized { self.recordFailure(peer) }
                        self.reply(reply, on: connection)
                    }
                }
            } else if complete || error != nil || buffer.count >= RemoteWire.maximumBytes {
                connection.cancel()
            } else {
                self.read(connection, peer: peer, buffer: buffer, exchange: exchange)
            }
        }
    }

    private func reply(_ reply: RemoteReply, on connection: NWConnection) {
        guard let data = try? RemoteWire.encode(reply) else { connection.cancel(); return }
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func isRateLimited(_ peer: String) -> Bool {
        let recent = (failures[peer] ?? []).filter { $0.timeIntervalSinceNow > -Self.failureWindow }
        failures[peer] = recent.isEmpty ? nil : recent
        return recent.count >= Self.failureLimit
    }

    private func recordFailure(_ peer: String) {
        failures[peer, default: []].append(Date())
    }

    /// Leaves a dispatch group once; only touched on `queue`.
    private final class Pending: @unchecked Sendable {
        private var waiting = true
        func leave(_ group: DispatchGroup) {
            guard waiting else { return }
            waiting = false
            group.leave()
        }
    }

    private static func peerHost(_ connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint { return "\(host)" }
        return "unknown"
    }
}
