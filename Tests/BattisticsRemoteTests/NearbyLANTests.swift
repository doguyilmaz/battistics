import Foundation
import Network
import Testing
@testable import BattisticsRemote

@Suite("Nearby LAN loopback", .serialized)
@MainActor
struct NearbyLANTests {
    @Test func aRealTLSConnectionAuthenticatesAndReturnsACommandAnswer() async throws {
        let credential = try NearbyCredential(macID: "loopback-test", key: Data(repeating: 19, count: 32))
        let parameters = NearbyTLS.parameters(credential)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        let port = RemoteTestGate<NWEndpoint.Port>()
        let accepted = RemoteTestGate<NearbyPeer>()
        listener.stateUpdateHandler = { state in
            if case .ready = state, let bound = listener.port { Task { await port.finish(bound) } }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let link = NearbyLANLink(connection: connection)
                let peer = NearbyPeer(link: link, credential: credential, server: true)
                peer.onMessage = { [weak peer] message in
                    if case .command(let id, let command) = message {
                        var status = RemoteStatus(machineName: "Dummy Mac", readAt: .now)
                        status.lastCommand = .init(id: command.id, failure: nil)
                        try? peer?.send(.status(id: id, status: status))
                    }
                }
                link.onReady = { [weak peer] in peer?.begin() }
                await accepted.finish(peer)
                link.start()
            }
        }
        listener.start(queue: .main)
        defer { listener.cancel() }
        let bound = try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(5))) { await port.value() }
        let link = NearbyLANLink(connection: NWConnection(host: "127.0.0.1", port: bound, using: NearbyTLS.parameters(credential)))
        let peer = NearbyPeer(link: link, credential: credential, server: false)
        let ready = RemoteTestGate<Bool>()
        peer.onReady = { Task { await ready.finish(true) } }
        link.start()
        defer { peer.close() }
        _ = try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(5))) { await ready.value() }
        let request = RemoteRequest(operation: .stop)
        let answer = try await peer.request(request, until: .now.advanced(by: .seconds(2)))
        #expect(answer.lastCommand?.id == request.id)
        #expect(answer.lastCommand?.failure == nil)
        let server = await accepted.value()
        server.close()
    }

    @Test func anUntrustedTLSKeyNeverReachesCommandDispatch() async throws {
        let credential = try NearbyCredential(macID: "loopback-rejection", key: Data(repeating: 21, count: 32))
        let wrong = try NearbyCredential(macID: credential.macID, key: Data(repeating: 22, count: 32))
        let parameters = NearbyTLS.parameters(credential)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        let port = RemoteTestGate<NWEndpoint.Port>()
        let server = RemoteTestGate<NearbyPeer>()
        listener.stateUpdateHandler = { state in
            if case .ready = state, let bound = listener.port { Task { await port.finish(bound) } }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let link = NearbyLANLink(connection: connection)
                let peer = NearbyPeer(link: link, credential: credential, server: true)
                peer.onReady = { Issue.record("An untrusted key authenticated") }
                peer.onMessage = { _ in Issue.record("Untrusted peer reached dispatch") }
                link.onReady = { [weak peer] in peer?.begin() }
                await server.finish(peer)
                link.start()
            }
        }
        listener.start(queue: .main)
        defer { listener.cancel() }
        let bound = try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(5))) { await port.value() }
        let link = NearbyLANLink(connection: NWConnection(host: "127.0.0.1", port: bound, using: NearbyTLS.parameters(wrong)))
        let peer = NearbyPeer(link: link, credential: wrong, server: false)
        let rejected = RemoteTestGate<Bool>()
        peer.onClosed = { Task { await rejected.finish(true) } }
        peer.onReady = { Issue.record("TLS accepted the wrong capability") }
        link.start()
        defer { peer.close() }
        _ = try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(5))) { await rejected.value() }
        let accepted = await server.value()
        accepted.close()
    }
}
