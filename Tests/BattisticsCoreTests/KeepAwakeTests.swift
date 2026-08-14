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

    @Test func onlyLidClosedModeRequiresWallPower() {
        // PreventSystemSleep is the only assertion macOS honours with the
        // display shut, and it is ignored on battery.
        #expect(KeepAwakeMode.lidClosed.requiresExternalPower)
        #expect(!KeepAwakeMode.displayOn.requiresExternalPower)
        #expect(!KeepAwakeMode.displayMaySleep.requiresExternalPower)
    }

    @Test func everyModeMapsToADistinctIOKitAssertionType() {
        let types = Set(KeepAwakeMode.allCases.map(\.assertionType))
        #expect(types.count == KeepAwakeMode.allCases.count)
        #expect(KeepAwakeMode.displayOn.assertionType == "PreventUserIdleDisplaySleep")
        #expect(KeepAwakeMode.displayMaySleep.assertionType == "PreventUserIdleSystemSleep")
        #expect(KeepAwakeMode.lidClosed.assertionType == "PreventSystemSleep")
    }
}
