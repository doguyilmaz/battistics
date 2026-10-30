import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Remote command lifetime")
struct RemoteCommandTests {
    @Test func aStalledWriteCannotKeepTheCommandSpinnerRunning() async {
        let gate = RemoteTestGate<Bool>()
        let writes = CloudKitBuffer(0)
        let reads = CloudKitBuffer(0)
        let started = ContinuousClock.now
        await #expect(throws: RemoteDeadline.Failure.self) {
            try await RemoteCommandExecutor.execute(.init(operation: .start), macID: "mac",
                timeout: .milliseconds(60), pollInterval: .milliseconds(1),
                write: { _, _ in writes.update { $0 += 1 }; _ = await gate.value() },
                read: { _ in reads.update { $0 += 1 }; return nil }, cleanup: { _ in })
        }
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(writes.read() == 1)
        #expect(reads.read() == 0)
        await gate.finish(true)
    }

    @Test func aStalledAnswerAndCleanupCannotExtendTheDeadline() async {
        let answer = RemoteTestGate<RemoteStatus?>()
        let cleanup = RemoteTestGate<Bool>()
        let cleanupEntered = RemoteTestGate<Bool>()
        let started = ContinuousClock.now
        await #expect(throws: RemoteDeadline.Failure.self) {
            try await RemoteCommandExecutor.execute(.init(operation: .stop), macID: "mac",
                timeout: .milliseconds(60), pollInterval: .milliseconds(1), write: { _, _ in },
                read: { _ in await answer.value() },
                cleanup: { _ in await cleanupEntered.finish(true); _ = await cleanup.value() })
        }
        #expect(started.duration(to: .now) < .seconds(2))
        _ = await cleanupEntered.value()
        await answer.finish(nil)
        await cleanup.finish(true)
    }

    @Test func onlyTheMatchingAnswerFinishesTheCommandAndItIsWrittenOnce() async throws {
        let request = RemoteRequest(operation: .start)
        let writes = CloudKitBuffer(0)
        let reads = CloudKitBuffer(0)
        let status = try await RemoteCommandExecutor.execute(request, macID: "mac",
            timeout: .seconds(2), pollInterval: .milliseconds(1),
            write: { sent, _ in #expect(sent.id == request.id); writes.update { $0 += 1 } },
            read: { _ in
                reads.update { $0 += 1 }
                var status = RemoteStatus(machineName: "Mac", readAt: .now)
                status.lastCommand = .init(id: reads.read() == 1 ? "another-command" : request.id, failure: nil)
                return status
            }, cleanup: { _ in Issue.record("Confirmed command must not be deleted by the phone") })
        #expect(status.lastCommand?.id == request.id)
        #expect(writes.read() == 1)
        #expect(reads.read() == 2)
    }

    @Test func aRefusalIsAnAnswerNotAnotherAttemptToStart() async throws {
        let request = RemoteRequest(operation: .start)
        var refused = RemoteStatus(machineName: "Mac", readAt: .now)
        refused.lastCommand = .init(id: request.id, failure: .init(.busy))
        let answer = refused
        let writes = CloudKitBuffer(0)
        let status = try await RemoteCommandExecutor.execute(request, macID: "mac",
            timeout: .seconds(2), pollInterval: .milliseconds(1),
            write: { _, _ in writes.update { $0 += 1 } }, read: { _ in answer }, cleanup: { _ in })
        #expect(status.lastCommand?.failure?.code == .busy)
        #expect(writes.read() == 1)
    }

    @Test func cancellationStopsTheCommandWithoutWaitingForItsAnswer() async {
        let entered = RemoteTestGate<Bool>()
        let answer = RemoteTestGate<RemoteStatus?>()
        let work = Task {
            try await RemoteCommandExecutor.execute(.init(operation: .stop), macID: "mac",
                timeout: .seconds(20), pollInterval: .milliseconds(1), write: { _, _ in },
                read: { _ in await entered.finish(true); return await answer.value() }, cleanup: { _ in })
        }
        _ = await entered.value()
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        await answer.finish(nil)
    }
}
