import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Bounded remote requests")
struct RemoteDeadlineTests {
    @Test func anExpiredDeadlineDoesNotStartWork() async {
        let started = CloudKitBuffer(false)
        await #expect(throws: RemoteDeadline.Failure.self) {
            try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(-1))) {
                started.update { $0 = true }
                return 42
            }
        }
        #expect(!started.read())
    }

    @Test func aSlowSuccessfulAnswerIsNotDiscardedBeforeItsDeadline() async throws {
        let value = try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(2))) {
            try await Task.sleep(for: .milliseconds(40))
            return 42
        }
        #expect(value == 42)
    }

    @Test func timeoutDoesNotWaitForAnUncooperativeService() async {
        let gate = RemoteTestGate<Int>()
        let started = ContinuousClock.now
        await #expect(throws: RemoteDeadline.Failure.self) {
            try await RemoteDeadline.perform(until: .now.advanced(by: .milliseconds(40))) {
                await gate.value()
            }
        }
        #expect(started.duration(to: .now) < .seconds(2))
        await gate.finish(42)
    }

    @Test func cancellationStopsWaitingForAnUncooperativeService() async {
        let gate = RemoteTestGate<Int>()
        let entered = RemoteTestGate<Bool>()
        let work = Task {
            try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(20))) {
                await entered.finish(true)
                return await gate.value()
            }
        }
        _ = await entered.value()
        let cancelled = ContinuousClock.now
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(cancelled.duration(to: .now) < .seconds(2))
        await gate.finish(42)
    }
}
