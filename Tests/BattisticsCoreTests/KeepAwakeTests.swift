import Foundation
import Testing

@testable import BattisticsCore

@Suite("Keep awake")
struct KeepAwakeTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func timedSessionsCarryADeadline() {
        let session = KeepAwakeSession(mode: .displayOn, duration: .oneHour, startedAt: start)
        #expect(session.deadline == start.addingTimeInterval(3600))
    }

    @Test func indefiniteSessionsNeverExpire() {
        let session = KeepAwakeSession(mode: .displayOn, duration: .indefinite, startedAt: start)
        #expect(session.deadline == nil)
        #expect(session.remaining(at: start.addingTimeInterval(86400 * 7)) == nil)
        #expect(!session.hasExpired(at: start.addingTimeInterval(86400 * 7)))
    }

    @Test func remainingCountsDownAndFloorsAtZero() {
        let session = KeepAwakeSession(mode: .displayOn, duration: .fifteenMinutes, startedAt: start)
        #expect(session.remaining(at: start) == 900)
        #expect(session.remaining(at: start.addingTimeInterval(300)) == 600)
        // Never negative: the UI shows this straight to the user.
        #expect(session.remaining(at: start.addingTimeInterval(5000)) == 0)
    }

    @Test func expiryIsInclusiveOfTheDeadline() {
        let session = KeepAwakeSession(mode: .displayOn, duration: .fifteenMinutes, startedAt: start)
        #expect(!session.hasExpired(at: start.addingTimeInterval(899)))
        #expect(session.hasExpired(at: start.addingTimeInterval(900)))
    }

    @Test func extendingAddsToTheDeadlineUpToTwelveHoursFromNow() {
        let session = KeepAwakeSession(mode: .displayOn, duration: .oneHour, startedAt: start)
        let later = start.addingTimeInterval(1800)
        #expect(session.extended(byMinutes: 30, now: later)?.deadline == start.addingTimeInterval(5400))
        #expect(session.extended(byMinutes: 30, now: later)?.startedAt == start)
        // Past its deadline but not yet stopped, the time counts from now.
        let overdue = start.addingTimeInterval(4000)
        #expect(session.extended(byMinutes: 15, now: overdue)?.deadline == overdue.addingTimeInterval(900))
        let long = KeepAwakeSession(mode: .displayOn, duration: .twelveHours, startedAt: start)
        #expect(long.extended(byMinutes: 60, now: start) == nil)
        #expect(long.extended(byMinutes: 60, now: start.addingTimeInterval(1800))?.deadline
                == start.addingTimeInterval(1800 + 12 * 3600))
        #expect(KeepAwakeSession(mode: .displayOn, duration: .indefinite, startedAt: start)
            .extended(byMinutes: 30, now: start) == nil)
    }

    @Test func durationRawValueIsItsMinutesSoItPersistsAsOneInteger() {
        #expect(KeepAwakeDuration.fifteenMinutes.minutes == 15)
        #expect(KeepAwakeDuration.twelveHours.minutes == 720)
        #expect(KeepAwakeDuration.indefinite.minutes == nil)
        #expect(KeepAwakeDuration(rawValue: 240) == .fourHours)
    }

    @Test func durationsAreOfferedShortestFirstWithIndefiniteLast() {
        let all = KeepAwakeDuration.allCases
        #expect(all.last == .indefinite)
        let timed = all.dropLast().map(\.rawValue)
        #expect(timed == timed.sorted())
        #expect(timed == [15, 30, 60, 120, 240, 360, 720])
    }

    @Test func displayAndSystemSleepUseSeparateAssertions() {
        #expect(KeepAwakeMode.displayOn.assertionType == "PreventUserIdleDisplaySleep")
        #expect(KeepAwakeMode.displayMaySleep.assertionType == "PreventUserIdleSystemSleep")
        #expect(KeepAwakeMode.lidClosed.assertionType == "PreventUserIdleSystemSleep")
    }
}

@Suite("Keep awake handover")
struct KeepAwakeHandoverTests {
    private let saved = Date(timeIntervalSince1970: 1_700_000_000)

    private func handover(_ duration: KeepAwakeDuration = .oneHour) -> KeepAwakeHandover {
        KeepAwakeHandover(
            session: KeepAwakeSession(mode: .displayOn, duration: duration, startedAt: saved.addingTimeInterval(-600)),
            origin: "manual", name: nil, savedAt: saved, uptime: 1000)
    }

    @Test func quickRelaunchResumes() {
        #expect(handover().outcome(now: saved.addingTimeInterval(8), uptime: 1008) == .resume)
    }

    @Test func sleepInBetweenEndsIt() {
        #expect(handover().outcome(now: saved.addingTimeInterval(60), uptime: 1010) == .slept)
    }

    @Test func restartInBetweenEndsIt() {
        #expect(handover().outcome(now: saved.addingTimeInterval(60), uptime: 40) == .slept)
    }

    @Test func deadlinePassedInBetweenEndsIt() {
        let quarter = handover(.fifteenMinutes)
        #expect(quarter.outcome(now: saved.addingTimeInterval(400), uptime: 1400) == .expired)
    }

    @Test func slowRelaunchIsNotAnUpdate() {
        #expect(handover(.indefinite).outcome(now: saved.addingTimeInterval(300), uptime: 1300) == .stale)
    }

    @Test func clockSetBackIsNotTrusted() {
        #expect(handover().outcome(now: saved.addingTimeInterval(-30), uptime: 1010) == .stale)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = handover()
        let decoded = try JSONDecoder().decode(KeepAwakeHandover.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
