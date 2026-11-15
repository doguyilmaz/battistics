import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Authenticated nearby protocol")
struct NearbyProtocolTests {
    private static func credential(_ byte: UInt8 = 7, macID: String = "test-mac") throws -> NearbyCredential {
        try .init(macID: macID, key: Data(repeating: byte, count: 32))
    }

    private static func authenticated() throws -> (NearbySession, NearbySession) {
        let credential = try credential()
        var server = NearbySession(credential: credential, server: true)
        var client = NearbySession(credential: credential, server: false)
        let proof = try #require(client.receive(server.begin()).response)
        let welcome = try #require(server.receive(proof).response)
        _ = try client.receive(welcome)
        #expect(server.authenticated && client.authenticated)
        return (server, client)
    }

    @Test func onlyAnAuthenticatedClientCanSendCommands() throws {
        var (server, client) = try Self.authenticated()
        let request = RemoteRequest(operation: .extend, durationMinutes: 30)
        let encoded = try client.seal(.command(id: UUID(), request: request))
        #expect(encoded.range(of: Data("durationMinutes".utf8)) == nil)
        guard case .command(_, let decoded) = try server.receive(encoded).message else { Issue.record("Missing command"); return }
        #expect(decoded.isSameCommand(as: request))
    }

    @Test func wrongKeysAndAnotherMacCannotAuthenticate() throws {
        for credential in [try Self.credential(8), try Self.credential(macID: "another-mac")] {
            var server = NearbySession(credential: try Self.credential(), server: true)
            var client = NearbySession(credential: credential, server: false)
            let proof = try #require(client.receive(server.begin()).response)
            #expect(throws: (any Error).self) { try server.receive(proof) }
            #expect(!server.authenticated)
        }
    }

    @Test func replayedProofCannotOpenAnotherConnection() throws {
        let credential = try Self.credential()
        var original = NearbySession(credential: credential, server: true)
        var next = NearbySession(credential: credential, server: true)
        var client = NearbySession(credential: credential, server: false)
        let proof = try #require(client.receive(original.begin()).response)
        _ = try next.begin()
        #expect(throws: (any Error).self) { try next.receive(proof) }
    }

    @Test func packetsRejectReplayReflectionReorderingAndTampering() throws {
        var (server, client) = try Self.authenticated()
        let packet = try client.seal(.read(id: UUID()))
        let later = try client.seal(.read(id: UUID()))
        #expect(throws: (any Error).self) { try server.receive(later) }
        _ = try server.receive(packet)
        #expect(throws: (any Error).self) { try server.receive(packet) }
        _ = try server.receive(later)
        let response = try server.seal(.ready)
        #expect(throws: (any Error).self) { try server.receive(response) }
        guard case .encrypted(let sequence, var body) = try RemoteWire.decode(NearbyPacket.self, from: client.seal(.read(id: UUID()))) else { return }
        body[body.startIndex + 1] ^= 1
        let altered = try RemoteWire.encode(NearbyPacket.encrypted(sequence: sequence, body: body))
        #expect(throws: (any Error).self) { try server.receive(altered) }
    }

    @Test func messagesCannotBeSentBeforeAuthentication() throws {
        var client = NearbySession(credential: try Self.credential(), server: false)
        #expect(throws: (any Error).self) { try client.seal(.command(id: UUID(), request: .init(operation: .stop))) }
    }

    @Test func framesSurviveGATTFragmentationAndCoalescedTCPReads() throws {
        let payloads = [Data(repeating: 3, count: 6000), Data(repeating: 4, count: 3000)]
        let stream = try payloads.reduce(into: Data()) { $0.append(try NearbyFrameBuffer.frame($1)) }
        var buffer = NearbyFrameBuffer()
        var recovered: [Data] = []
        for byte in stream { recovered += try buffer.append(Data([byte])) }
        #expect(recovered == payloads)
        var combined = NearbyFrameBuffer()
        #expect(try combined.append(stream) == payloads)
    }

    @Test func anUntrustedLengthIsRejectedBeforeBufferingItsPayload() throws {
        var buffer = NearbyFrameBuffer()
        #expect(throws: (any Error).self) { try buffer.append(Data([0xff, 0xff, 0xff, 0xff])) }
        #expect(throws: (any Error).self) { try NearbyFrameBuffer.frame(Data(repeating: 0, count: NearbyFrameBuffer.maximumPayload + 1)) }
    }

    @Test func anOlderCloudReplyCannotReplaceANewerNearbyReading() {
        var local = RemoteStatus(machineName: "Mac", readAt: .now.addingTimeInterval(-10))
        local.revision = 42
        var cloud = RemoteStatus(machineName: "Mac", readAt: .now)
        cloud.revision = 41
        #expect(!cloud.isAtLeastAsRecent(as: local))
        #expect(local.isAtLeastAsRecent(as: cloud))
        cloud.revision = nil
        #expect(cloud.isAtLeastAsRecent(as: local))
    }
}
