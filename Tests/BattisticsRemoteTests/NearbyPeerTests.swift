import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Nearby connection lifecycle")
@MainActor
struct NearbyPeerTests {
    private static func pair(clock: @escaping () -> ContinuousClock.Instant = { .now }) throws -> (NearbyPeer, NearbyPeer) {
        let credential = try NearbyCredential(macID: "test-mac", key: Data(repeating: 5, count: 32))
        let incoming = NearbyTestLink(), outgoing = NearbyTestLink()
        incoming.remote = outgoing
        outgoing.remote = incoming
        let server = NearbyPeer(link: incoming, credential: credential, server: true, clock: clock)
        let client = NearbyPeer(link: outgoing, credential: credential, server: false, clock: clock)
        server.begin()
        return (server, client)
    }

    @Test func heartbeatsAndCommandAnswersAreAcknowledgedAfterAuthentication() async throws {
        let (server, client) = try Self.pair()
        defer { client.close(); server.close() }
        #expect(server.healthy && client.healthy)
        let heartbeat = UUID()
        var acknowledgements: [UUID] = []
        server.onMessage = { [weak server] message in
            switch message {
            case .acknowledged(let id): acknowledgements.append(id)
            case .command(let id, let request):
                var status = RemoteStatus(machineName: "Mac", readAt: .now)
                status.lastCommand = .init(id: request.id, failure: nil)
                try? server?.send(.status(id: id, status: status))
            default: Issue.record("Unexpected message")
            }
        }
        try server.send(.status(id: heartbeat, status: .init(machineName: "Mac", readAt: .now)))
        #expect(acknowledgements == [heartbeat])
        let request = RemoteRequest(operation: .extend, durationMinutes: 30)
        let answer = try await client.request(request, until: .now.advanced(by: .seconds(1)))
        #expect(answer.lastCommand?.id == request.id)
        #expect(acknowledgements.count == 2)
        #expect(server.healthy && client.healthy)
    }

    @Test func disconnectReleasesAPendingCommandImmediately() async throws {
        let (server, client) = try Self.pair()
        defer { client.close(); server.close() }
        let arrived = RemoteTestGate<Bool>()
        server.onMessage = { message in
            if case .command = message { Task { await arrived.finish(true) } }
        }
        let work = Task { try await client.request(.init(operation: .stop), until: .now.advanced(by: .seconds(5))) }
        _ = await arrived.value()
        server.close()
        await #expect(throws: NearbyError.self) { try await work.value }
        #expect(!server.healthy && !client.healthy)
    }

    @Test func aDelayedPhoneCanRecoverThroughTheNextHeartbeat() throws {
        var now = ContinuousClock.now
        let (server, client) = try Self.pair(clock: { now })
        defer { client.close(); server.close() }
        now = now.advanced(by: .seconds(100))
        #expect(!server.healthy && !client.healthy)
        #expect(server.authenticated && client.authenticated)
        try server.send(.status(id: UUID(), status: .init(machineName: "Mac", readAt: .now)))
        #expect(server.healthy && client.healthy)
    }

    @Test func aLostAnswerClosesTheSessionAtItsDeadline() async throws {
        let (server, client) = try Self.pair()
        defer { client.close(); server.close() }
        await #expect(throws: RemoteDeadline.Failure.self) {
            try await client.request(.init(operation: .stop), until: .now.advanced(by: .milliseconds(20)))
        }
        #expect(!server.healthy && !client.healthy)
    }
}
