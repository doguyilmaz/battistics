import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Notification evidence and repeat suppression")
struct RemoteAlertPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func status(_ seconds: Double = 0, percent: Int = 50,
                        thermal: RemoteStatus.Thermal = .nominal) -> RemoteStatus {
        RemoteStatus(machineName: "Mac", readAt: start.addingTimeInterval(seconds),
                     battery: .init(percent: percent, isCharging: false, onAdapter: false, minutesRemaining: 300),
                     session: .init(mode: .lidClosed, origin: .phone, startedAt: start, deadline: nil),
                     thermal: thermal, heartbeatSeconds: RemoteStatus.sessionHeartbeat)
    }

    @Test func aMissingPushOrOneStaleReadCannotWarn() {
        var state = RemoteSilenceState()
        let reading = status()
        #expect(state.observe(reading, now: start.addingTimeInterval(600)) == false)
        #expect(state.observe(reading, now: start.addingTimeInterval(1800)) == false)
        #expect(state.observe(reading, now: start.addingTimeInterval(1919)) == false)
        #expect(state.observe(reading, now: start.addingTimeInterval(1920)) == true)
        #expect(state.observe(reading, now: start.addingTimeInterval(3000)) == false)
    }

    @Test func failedFetchAndNewerOldRecordRestartConfirmation() {
        var state = RemoteSilenceState()
        #expect(state.observe(status(), now: start.addingTimeInterval(1800)) == false)
        state.interrupt()
        #expect(state.observe(status(), now: start.addingTimeInterval(2000)) == false)
        #expect(state.observe(status(120), now: start.addingTimeInterval(2120)) == false)
        #expect(state.observe(status(120), now: start.addingTimeInterval(2240)) == true)
    }

    @Test func aSingleRecoveryCannotRearmTheSameOutageEvenAfterRelaunch() throws {
        var state = RemoteSilenceState()
        _ = state.observe(status(), now: start.addingTimeInterval(1800))
        #expect(state.observe(status(), now: start.addingTimeInterval(1920)) == true)
        #expect(state.observe(status(2000), now: start.addingTimeInterval(2000)) == false)
        state = try RemoteWire.decode(RemoteSilenceState.self, from: RemoteWire.encode(state))
        #expect(state.observe(status(2000), now: start.addingTimeInterval(3800)) == false)
        #expect(state.observe(status(2000), now: start.addingTimeInterval(3920)) == false)
    }

    @Test func tenMinutesOfFreshReadingsRearmANewOutage() {
        var state = RemoteSilenceState()
        _ = state.observe(status(), now: start.addingTimeInterval(1800))
        #expect(state.observe(status(), now: start.addingTimeInterval(1920)) == true)
        for time in stride(from: 2000.0, through: 2600, by: 120) {
            #expect(state.observe(status(time), now: start.addingTimeInterval(time)) == false)
        }
        #expect(state.observe(status(2600), now: start.addingTimeInterval(4400)) == false)
        #expect(state.observe(status(2600), now: start.addingTimeInterval(4520)) == true)
    }

    @Test func sleepExpiredSessionsAndAnotherMacDoNotShareSilenceState() {
        var state = RemoteSilenceState()
        var sleeping = status()
        sleeping.sleptAt = start
        #expect(state.observe(sleeping, now: start.addingTimeInterval(1800)) == false)
        #expect(state.observe(sleeping, now: start.addingTimeInterval(2000)) == false)
        var expired = status()
        expired.session?.deadline = start.addingTimeInterval(600)
        #expect(state.observe(expired, now: start.addingTimeInterval(1800)) == false)
        #expect(state.observe(expired, now: start.addingTimeInterval(2000)) == false)
        var otherMac = RemoteSilenceState()
        #expect(state.observe(status(), now: start.addingTimeInterval(1800)) == false)
        #expect(state.observe(status(), now: start.addingTimeInterval(1920)) == true)
        #expect(otherMac.observe(status(), now: start.addingTimeInterval(1920)) == false)
    }

    @Test func clockChangesAndFailedRecoveryDoNotGrantAnotherAlert() {
        var state = RemoteSilenceState()
        _ = state.observe(status(), now: start.addingTimeInterval(1800))
        #expect(state.observe(status(), now: start.addingTimeInterval(1700)) == false)
        #expect(state.observe(status(), now: start.addingTimeInterval(1800)) == false)
        #expect(state.observe(status(), now: start.addingTimeInterval(1920)) == true)
        _ = state.observe(status(2000), now: start.addingTimeInterval(2000))
        state.interrupt()
        _ = state.observe(status(2700), now: start.addingTimeInterval(2700))
        _ = state.observe(status(2700), now: start.addingTimeInterval(4500))
        #expect(state.observe(status(2700), now: start.addingTimeInterval(4620)) == false)
    }

    @Test func thermalJitterStaysLatchedAndStableRecoveryRearms() {
        var state = RemoteAlertState()
        #expect(state.filter([.runningHot], status: status(0, thermal: .serious)) == [.runningHot])
        _ = state.filter([], status: status(120, thermal: .fair))
        #expect(state.filter([.runningHot], status: status(240, thermal: .serious)).isEmpty)
        for time in stride(from: 360.0, through: 960, by: 120) {
            _ = state.filter([], status: status(time))
        }
        #expect(state.filter([.runningHot], status: status(1080, thermal: .critical)) == [.runningHot])
    }

    @Test func anUnobservedRecoveryCannotRearmHeat() {
        var state = RemoteAlertState()
        _ = state.filter([.runningHot], status: status(0, thermal: .serious))
        _ = state.filter([], status: status(120))
        _ = state.filter([], status: status(1200))
        #expect(state.filter([.runningHot], status: status(1320, thermal: .serious)).isEmpty)
    }

    @Test func chargeTargetsKeepTheirOwnPerChargeRearming() {
        var state = RemoteAlertState()
        #expect(state.filter([.chargeReached(percent: 80)], status: status()) == [.chargeReached(percent: 80)])
        #expect(state.filter([.chargeReached(percent: 80)], status: status(120)) == [.chargeReached(percent: 80)])
    }

    @Test func batteryJitterAndBriefChargingCannotRepeatTheWarning() {
        var state = RemoteAlertState()
        #expect(state.filter([.batteryLow(percent: 20)], status: status(0, percent: 20)) == [.batteryLow(percent: 20)])
        _ = state.filter([], status: status(120, percent: 21))
        #expect(state.filter([.batteryLow(percent: 20)], status: status(240, percent: 20)).isEmpty)
        var plugged = status(360, percent: 20)
        plugged.battery?.onAdapter = true
        _ = state.filter([], status: plugged)
        #expect(state.filter([.batteryLow(percent: 19)], status: status(480, percent: 19)).isEmpty)
        for time in stride(from: 600.0, through: 1200, by: 120) {
            _ = state.filter([], status: status(time, percent: 26))
        }
        #expect(state.filter([.batteryLow(percent: 20)], status: status(1320, percent: 20)) == [.batteryLow(percent: 20)])
    }

    @Test func networkWarningsAndRuntimeAreOncePerSessionAndSurviveRelaunch() throws {
        var state = RemoteAlertState()
        #expect(state.filter([.unpluggedWithoutHotspot, .batteryRunsOut(minutesLeft: 90)], status: status()).count == 2)
        state = try RemoteWire.decode(RemoteAlertState.self, from: RemoteWire.encode(state))
        #expect(state.filter([.closedLidWithoutHotspot, .batteryRunsOut(minutesLeft: 80)], status: status(120)).isEmpty)
        var nextSession = status(240)
        nextSession.session?.startedAt = nextSession.readAt
        #expect(state.filter([.closedLidWithoutHotspot, .batteryRunsOut(minutesLeft: 80)], status: nextSession).count == 2)
    }

    @Test(arguments: [RemoteStatus.EndReason.user, .phone, .client])
    func deliberateStopsAndTaskCompletionStaySilent(_ reason: RemoteStatus.EndReason) {
        var ended = status(120)
        ended.session = nil
        ended.lastEnd = .init(reason: reason, at: ended.readAt)
        #expect(RemoteAlert.pushed(from: status(), to: ended).isEmpty)
        #expect(RemoteAlert.alerts(from: status(), to: ended, now: ended.readAt).isEmpty)
    }

    @Test(arguments: [RemoteStatus.EndReason.battery, .thermal, .failure, .slept, .timer])
    func protectionAndUnexpectedEndsStillNotify(_ reason: RemoteStatus.EndReason) {
        var ended = status(120)
        ended.session = nil
        ended.lastEnd = .init(reason: reason, at: ended.readAt)
        #expect(RemoteAlert.pushed(from: status(), to: ended) == [.sessionEnded(reason)])
    }

    @Test func anEndFromBeforeTheObservedSessionIsNotANewEvent() {
        var ended = status(120)
        ended.session = nil
        ended.lastEnd = .init(reason: .failure, at: start.addingTimeInterval(-60))
        #expect(RemoteAlert.pushed(from: status(), to: ended).isEmpty)
    }

    @Test func onlyUserSelectedDeadlinesScheduleReminders() {
        var reading = status()
        #expect(RemoteReminderPolicy.endingDate(for: reading, now: start) == nil)
        reading.session?.deadline = start.addingTimeInterval(3600)
        #expect(RemoteReminderPolicy.endingDate(for: reading, now: start) == start.addingTimeInterval(3300))
        #expect(RemoteReminderPolicy.endingDate(for: reading, now: start.addingTimeInterval(3300)) == nil)
        for origin: RemoteStatus.Origin in [.ai, .terminal] {
            reading.session?.origin = origin
            #expect(RemoteReminderPolicy.endingDate(for: reading, now: start) == nil)
        }
        reading.session?.origin = .phone
        reading.sleptAt = start
        #expect(RemoteReminderPolicy.endingDate(for: reading, now: start) == nil)
    }

    @Test func outboxPersistsUncertainSavesAndNeverRegeneratesTheirID() throws {
        var outbox = RemoteAlertOutbox()
        outbox.record(from: status(), to: status(120, thermal: .serious))
        let event = try #require(outbox.pending.first)
        outbox = try RemoteWire.decode(RemoteAlertOutbox.self, from: RemoteWire.encode(outbox))
        outbox.record(from: nil, to: status(240, thermal: .serious))
        #expect(outbox.pending.map(\.id) == [event.id])
        outbox.acknowledge(event.id)
        outbox.record(from: status(240), to: status(360, thermal: .serious))
        #expect(outbox.pending.isEmpty)
    }

    @Test func outboxDropsResolvedAndExpiredRisksBeforeRetrying() {
        var outbox = RemoteAlertOutbox()
        outbox.record(from: status(), to: status(120, thermal: .serious))
        outbox.record(from: status(120, thermal: .serious), to: status(240))
        #expect(outbox.pending.isEmpty)
        var another = RemoteAlertOutbox()
        another.record(from: status(), to: status(120, thermal: .serious))
        another.record(from: nil, to: status(720, thermal: .serious))
        #expect(another.pending.isEmpty)
    }
}
