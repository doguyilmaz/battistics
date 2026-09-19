import Foundation
import Testing

@testable import BattisticsCore

@Suite("Bounded command execution", .timeLimit(.minutes(1)))
struct BoundedCommandTests {
    @Test func collectsOutputThroughEOF() async throws {
        let output = try await BoundedCommand.run(
            executable: "/usr/bin/printf", arguments: ["battery:%s", "42"])
        #expect(String(decoding: output, as: UTF8.self) == "battery:42")
    }

    @Test func synchronousWorkerUsesTheSameOutputContract() throws {
        let output = try BoundedCommand.runSynchronously(
            executable: "/usr/bin/printf", arguments: ["charge"])
        #expect(String(decoding: output, as: UTF8.self) == "charge")
    }

    @Test func allowsOutputExactlyAtTheLimit() async throws {
        let output = try await BoundedCommand.run(
            executable: "/usr/bin/printf", arguments: ["1234"], maximumOutputBytes: 4)
        #expect(output.count == 4)
    }

    @Test func stopsAContinuouslyWritingChildAtTheLimit() async {
        await #expect(throws: BoundedCommand.Failure.outputLimitExceeded) {
            try await BoundedCommand.run(
                executable: "/usr/bin/yes", arguments: [],
                timeout: 5, maximumOutputBytes: 1_024)
        }
    }

    @Test func unusedStandardInputIsClosed() async throws {
        let output = try await BoundedCommand.run(
            executable: "/bin/cat", arguments: [], timeout: 2)
        #expect(output.isEmpty)
    }

    @Test func stderrCannotFillAnUnreadPipe() async {
        // More error output than a pipe buffer, without requiring a shell or
        // a fixture interpreter. None of these paths are created.
        let missingDirectory = "/battistics-missing-\(UUID().uuidString)"
        let arguments = (0..<2_048).map { "\(missingDirectory)/\($0)" }
        await #expect(throws: BoundedCommand.Failure.unsuccessfulExit(1)) {
            try await BoundedCommand.run(
                executable: "/bin/ls", arguments: arguments, timeout: 5)
        }
    }

    @Test func aQuietChildStillHasADeadline() async {
        let started = ContinuousClock.now
        await #expect(throws: BoundedCommand.Failure.timedOut) {
            try await BoundedCommand.run(
                executable: "/bin/sleep", arguments: ["30"], timeout: 0.05)
        }
        #expect(started.duration(to: .now) < .seconds(2))
    }

    @Test func cancellationBeforeLaunchDoesNotRunTheExecutable() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BoundedCommand.run(
                executable: "/battistics-missing-executable", arguments: [])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationAroundLaunchDoesNotLeaveTheCallerWaiting() async {
        let started = ContinuousClock.now
        let task = Task {
            try await BoundedCommand.run(
                executable: "/bin/sleep", arguments: ["30"], timeout: 10)
        }
        await Task.yield()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(started.duration(to: .now) < .seconds(2))
    }

    @Test func aLaunchFailureCompletesInsteadOfWaitingForTheDeadline() async {
        await #expect(throws: (any Error).self) {
            try await BoundedCommand.run(
                executable: "/battistics-missing-executable", arguments: [])
        }
    }

    @Test func invalidBoundsFailBeforeLaunching() async {
        await #expect(throws: BoundedCommand.Failure.invalidLimits) {
            try await BoundedCommand.run(
                executable: "/battistics-missing-executable", arguments: [], timeout: 0)
        }
        await #expect(throws: BoundedCommand.Failure.invalidLimits) {
            try await BoundedCommand.run(
                executable: "/battistics-missing-executable", arguments: [], maximumOutputBytes: -1)
        }
    }
}
