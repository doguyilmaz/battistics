import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Durable command admission")
struct RemoteCommandJournalTests {
    private static func path() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("battistics-journal-\(UUID()).json") }

    @Test func aLostReplyReturnsTheSavedResultAfterRelaunch() async throws {
        let url = Self.path()
        defer { try? FileManager.default.removeItem(at: url) }
        let request = RemoteRequest(operation: .extend, durationMinutes: 30)
        let first = RemoteCommandJournal(url: url)
        guard case .execute = try await first.claim(request) else { Issue.record("Not admitted"); return }
        try await first.complete(.init(id: request.id, failure: nil))
        let relaunched = RemoteCommandJournal(url: url)
        guard case .completed(let result) = try await relaunched.claim(request) else { Issue.record("Command would run again"); return }
        #expect(result.id == request.id && result.failure == nil)
    }

    @Test func anInterruptedCommandIsNotAutomaticallyReplayed() async throws {
        let url = Self.path()
        defer { try? FileManager.default.removeItem(at: url) }
        let request = RemoteRequest(operation: .start)
        _ = try await RemoteCommandJournal(url: url).claim(request)
        guard case .uncertain = try await RemoteCommandJournal(url: url).claim(request) else {
            Issue.record("A crash between admission and completion must not repeat the side effect"); return
        }
    }

    @Test func anIDCannotBeReusedForDifferentArguments() async throws {
        let url = Self.path()
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = RemoteCommandJournal(url: url)
        var request = RemoteRequest(operation: .extend, durationMinutes: 30)
        _ = try await journal.claim(request)
        request.durationMinutes = 60
        await #expect(throws: NearbyError.self) { try await journal.claim(request) }
    }

    @Test func oldAndImplausiblyFutureCommandsAreRejected() async {
        let now = Date()
        for sentAt in [now.addingTimeInterval(-RemoteRequest.lifetime), now.addingTimeInterval(31)] {
            let url = Self.path()
            defer { try? FileManager.default.removeItem(at: url) }
            await #expect(throws: NearbyError.self) {
                try await RemoteCommandJournal(url: url).claim(.init(operation: .stop, sentAt: sentAt), at: now)
            }
        }
    }

    @Test func revisionsAdvanceAcrossRelaunches() async throws {
        let url = Self.path()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = RemoteCommandJournal(url: url)
        #expect(try await first.nextRevision() == 1)
        #expect(try await first.nextRevision() == 2)
        #expect(try await RemoteCommandJournal(url: url).nextRevision() == 3)
    }

    @Test func failedPersistenceDoesNotAdmitOrConsumeACommand() async throws {
        let parent = Self.path()
        try Data([1]).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let journal = RemoteCommandJournal(url: parent.appendingPathComponent("journal.json"))
        let request = RemoteRequest(operation: .extend, durationMinutes: 30)
        await #expect(throws: (any Error).self) { try await journal.claim(request) }
        try FileManager.default.removeItem(at: parent)
        guard case .execute = try await journal.claim(request) else { Issue.record("Failed save consumed the ID"); return }
    }
}
