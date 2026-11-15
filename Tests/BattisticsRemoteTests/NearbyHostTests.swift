#if os(macOS)
import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Nearby host admission lifecycle")
@MainActor
struct NearbyHostTests {
    @Test func stalledUnauthenticatedPeersCannotOccupyEveryApplicationSlot() throws {
        let credential = try NearbyCredential(macID: "mac", key: Data(repeating: 40, count: 32))
        let host = NearbyHost(startsTransports: false)
        defer { host.stop() }
        host.start(credential, read: { Self.status() }, command: { Self.status($0) }, delivered: { _ in })
        var retained: [NearbyTestLink] = []
        for _ in 0..<8 {
            let incoming = NearbyTestLink(), silent = NearbyTestLink()
            incoming.remote = silent
            silent.remote = incoming
            retained.append(silent)
            #expect(host.accept(incoming) != nil)
        }
        let (server, client) = try Self.connect(host, credential: credential)
        defer { client.close(); for link in retained { link.close() } }
        #expect(server.authenticated && client.authenticated)
    }
    private static func status(_ request: RemoteRequest? = nil) -> RemoteStatus {
        var status = RemoteStatus(machineName: "Dummy Mac", readAt: .now)
        status.lastCommand = request.map { .init(id: $0.id, failure: nil) }
        return status
    }

    private static func connect(_ host: NearbyHost, credential: NearbyCredential, id: UUID = UUID()) throws -> (NearbyPeer, NearbyPeer) {
        let incoming = NearbyTestLink(id: id), outgoing = NearbyTestLink()
        incoming.remote = outgoing
        outgoing.remote = incoming
        let client = NearbyPeer(link: outgoing, credential: credential, server: false)
        let server = try #require(host.accept(incoming))
        #expect(server.authenticated && client.authenticated)
        return (server, client)
    }

    @Test func aQueuedRevokedCommandCannotUseReplacementSharingCallbacks() async throws {
        let credential = try NearbyCredential(macID: "mac", key: Data(repeating: 31, count: 32))
        let replacement = try NearbyCredential(macID: "mac", key: Data(repeating: 32, count: 32))
        let host = NearbyHost(startsTransports: false)
        defer { host.stop() }
        var oldEffects = 0, newEffects = 0
        host.start(credential, read: { Self.status() }, command: { request in
            oldEffects += 1
            return Self.status(request)
        }, delivered: { _ in })
        let (oldPeer, oldClient) = try Self.connect(host, credential: credential)
        defer { oldClient.close() }
        let release = RemoteTestGate<Bool>()
        let request = RemoteRequest(operation: .extend, durationMinutes: 30)
        let queued = Task {
            _ = await release.value()
            await host.process(.command(id: UUID(), request: request), from: oldPeer)
        }
        host.stop()
        host.start(replacement, read: { Self.status() }, command: { request in
            newEffects += 1
            return Self.status(request)
        }, delivered: { _ in })
        // Core Bluetooth can reuse a central identifier in a new session.
        let (newPeer, newClient) = try Self.connect(host, credential: replacement, id: oldPeer.link.id)
        defer { newClient.close() }
        await release.finish(true)
        await queued.value
        #expect(oldEffects == 0 && newEffects == 0)
        await host.process(.command(id: UUID(), request: request), from: newPeer)
        #expect(newEffects == 1)
    }

    @Test func aDisconnectedPeerCannotDispatchAPendingChange() async throws {
        let credential = try NearbyCredential(macID: "mac", key: Data(repeating: 33, count: 32))
        let host = NearbyHost(startsTransports: false)
        defer { host.stop() }
        var effects = 0
        host.start(credential, read: { Self.status() }, command: { request in
            effects += 1
            return Self.status(request)
        }, delivered: { _ in })
        let (peer, client) = try Self.connect(host, credential: credential)
        client.close()
        await host.process(.command(id: UUID(), request: .init(operation: .stop)), from: peer)
        #expect(effects == 0)
    }
}
#endif
