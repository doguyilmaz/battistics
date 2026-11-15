import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Remote transport handoff")
struct RemoteHandoffTests {
    @Test func revocationDuringNearbyFailureCannotSendToTheReplacementCloudAccount() async {
        let authorized = CloudKitBuffer(true)
        let route = RemoteRoute(kind: .lan) { _, _ in
            authorized.update { $0 = false }
            throw NearbyError.unavailable
        }
        await #expect(throws: CancellationError.self) {
            try await RemoteHandoff.execute(.init(operation: .stop), routes: [route], authorizing: { authorized.read() }) { _, _ in
                Issue.record("Revoked command crossed into the replacement CloudKit account")
                throw NearbyError.unavailable
            }
        }
    }
    private static func answer(_ request: RemoteRequest, failure: RemoteFailure? = nil) -> RemoteStatus {
        var status = RemoteStatus(machineName: "Mac", readAt: .now)
        status.lastCommand = .init(id: request.id, failure: failure)
        return status
    }

    @Test func aLostLANReplyFallsBackWithoutApplyingTheExtensionTwice() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = RemoteCommandJournal(url: url)
        let effects = CloudKitBuffer(0)
        let paths = CloudKitBuffer<[String]>([])
        let request = RemoteRequest(operation: .extend, durationMinutes: 30)
        let lan = RemoteRoute(kind: .lan) { incoming, _ in
            paths.update { $0.append("lan") }
            #expect(incoming.isSameCommand(as: request))
            if case .execute = try await journal.claim(incoming) {
                effects.update { $0 += 1 }
                try await journal.complete(.init(id: incoming.id, failure: nil))
            }
            throw NearbyError.unavailable
        }
        let ble = RemoteRoute(kind: .bluetooth) { incoming, _ in
            paths.update { $0.append("ble") }
            #expect(incoming.isSameCommand(as: request))
            guard case .completed = try await journal.claim(incoming) else { throw NearbyError.uncertainCommand }
            return Self.answer(incoming)
        }
        let result = try await RemoteHandoff.execute(request, routes: [lan, ble]) { command, _ in
            paths.update { $0.append("cloud") }
            return Self.answer(command)
        }
        #expect(result.lastCommand?.id == request.id)
        #expect(effects.read() == 1)
        #expect(paths.read() == ["lan", "ble"])
    }

    @Test func stalledNearbyWorkCannotHoldUpCloudFallback() async throws {
        let gate = RemoteTestGate<Bool>()
        let request = RemoteRequest(operation: .stop)
        let route = RemoteRoute(kind: .lan) { _, _ in _ = await gate.value(); throw NearbyError.unavailable }
        let started = ContinuousClock.now
        let answer = try await RemoteHandoff.execute(request, routes: [route], timeout: .seconds(1), localTimeout: .milliseconds(20)) { command, _ in
            #expect(command.isSameCommand(as: request))
            return Self.answer(command)
        }
        await gate.finish(true)
        #expect(started.duration(to: .now) < .seconds(1))
        #expect(answer.lastCommand?.id == request.id)
    }

    @Test func anExplicitMacRefusalDoesNotTryAnotherTransport() async throws {
        let route = RemoteRoute(kind: .lan) { request, _ in Self.answer(request, failure: .init(.busy)) }
        let result = try await RemoteHandoff.execute(.init(operation: .start), routes: [route]) { _, _ in
            Issue.record("A refusal must not be resent elsewhere"); throw NearbyError.unavailable
        }
        #expect(result.lastCommand?.failure?.code == .busy)
    }

    @Test func anUnrelatedAcknowledgementDoesNotCountAsSuccess() async throws {
        let route = RemoteRoute(kind: .lan) { _, _ in Self.answer(.init(operation: .stop)) }
        let request = RemoteRequest(operation: .start)
        let result = try await RemoteHandoff.execute(request, routes: [route]) { incoming, _ in Self.answer(incoming) }
        #expect(result.lastCommand?.id == request.id)
    }

    @Test func cancellationDoesNotSendOnAnotherTransport() async {
        let request = RemoteRequest(operation: .stop)
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RemoteHandoff.execute(request, routes: []) { _, _ in
                Issue.record("Cancelled operation sent a command"); throw NearbyError.unavailable
            }
        }
        await #expect(throws: CancellationError.self) { try await work.value }
    }
}
