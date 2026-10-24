import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Remote companion contract")
struct RemoteTests {
    @Test func batteryRunsOutFirstOnlyOnBattery() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var status = RemoteStatus(
            machineName: "Mac", readAt: now,
            battery: .init(percent: 30, isCharging: false, onAdapter: false, minutesRemaining: 60),
            session: .init(mode: .lidClosed, origin: .phone, startedAt: now, deadline: now.addingTimeInterval(7200)))
        #expect(status.batteryRunsOutFirst)
        status.session?.deadline = now.addingTimeInterval(1800)
        #expect(!status.batteryRunsOutFirst)
        status.session?.deadline = nil
        #expect(status.batteryRunsOutFirst)
        status.session?.deadline = now.addingTimeInterval(7200)
        status.battery?.onAdapter = true
        #expect(!status.batteryRunsOutFirst)
    }

    @Test func wireRoundTripsAndRejectsGarbage() throws {
        let request = RemoteRequest(operation: .start, mode: .displayMaySleep, durationMinutes: 60, deviceName: "iPhone",
                                    sentAt: Date(timeIntervalSince1970: 1_000_000))
        #expect(try RemoteWire.decode(RemoteRequest.self, from: RemoteWire.encode(request)) == request)
        #expect(throws: (any Error).self) { try RemoteWire.decode(RemoteRequest.self, from: Data("{}".utf8)) }
    }

    @Test func allowedDurationsIncludeUntilTurnedOffAndTelemetryRoundTrips() throws {
        #expect(RemoteRequest.allowedDurations.contains(0))
        #expect(RemoteRequest.allowedDurations == [0, 15, 30, 60, 120, 240, 360, 720])
        let now = Date(timeIntervalSince1970: 1_000_000)
        let status = RemoteStatus(
            machineName: "Mac", readAt: now,
            battery: .init(percent: 82, isCharging: true, onAdapter: true, minutesRemaining: 45,
                           healthPercent: 96, lowPowerMode: true, watts: 42.5, adapterWatts: 67,
                           temperatureC: 34.2, cycleCount: 118),
            session: .init(mode: .lidClosed, origin: .phone, name: "Dogu’s iPhone 16e", startedAt: now, deadline: nil),
            network: .hotspot, networkName: "Dogu’s iPhone 16e", lidClosed: true,
            protection: .init(closedLidAllowed: true))
        let decoded = try RemoteWire.decode(RemoteStatus.self, from: RemoteWire.encode(status))
        #expect(decoded == status)
        #expect(decoded.battery?.lowPowerMode == true)
        #expect(decoded.battery?.watts == 42.5)
        #expect(decoded.battery?.adapterWatts == 67)
        #expect(decoded.networkName == "Dogu’s iPhone 16e")
        #expect(decoded.session?.deadline == nil)
    }

    @Test func freshnessFollowsTheHeartbeat() {
        let status = RemoteStatus(machineName: "Mac", readAt: Date(timeIntervalSince1970: 1_000_000))
        #expect(status.isFresh(at: status.readAt.addingTimeInterval(RemoteStatus.heartbeat)))
        #expect(!status.isFresh(at: status.readAt.addingTimeInterval(RemoteStatus.heartbeat * 2 + 1)))
    }
}

@Suite("Phone alerts")
struct RemoteAlertTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func status(percent: Int = 50, adapter: Bool = false, minutes: Int? = 300, session: Bool = true,
                        ended: RemoteStatus.EndReason? = nil) -> RemoteStatus {
        RemoteStatus(
            machineName: "Mac", readAt: now,
            battery: .init(percent: percent, isCharging: false, onAdapter: adapter, minutesRemaining: minutes),
            session: session ? .init(mode: .lidClosed, origin: .phone, startedAt: now,
                                     deadline: now.addingTimeInterval(7200)) : nil,
            lastEnd: ended.map { .init(reason: $0, at: now) }, protection: .init(warnAtPercent: 20))
    }

    @Test func firstReadingAndRecoveryStaySilent() {
        #expect(RemoteAlert.alerts(from: .none, to: status(percent: 5)).isEmpty)
        #expect(RemoteAlert.alerts(from: .some(nil), to: status(percent: 5)).isEmpty)
    }

    @Test func sessionEndAlertsUnlessThePhoneStoppedIt() {
        #expect(RemoteAlert.alerts(from: status(), to: status(session: false, ended: .battery)) == [.sessionEnded(.battery)])
        #expect(RemoteAlert.alerts(from: status(), to: status(session: false, ended: .phone)).isEmpty)
    }

    @Test func batteryAlertsFireOnceWhenCrossing() {
        #expect(RemoteAlert.alerts(from: status(percent: 21), to: status(percent: 20)) == [.batteryLow(percent: 20)])
        #expect(RemoteAlert.alerts(from: status(percent: 20), to: status(percent: 19)).isEmpty)
        #expect(RemoteAlert.alerts(from: status(percent: 15, adapter: true), to: status(percent: 15)) == [.batteryLow(percent: 15)])
        #expect(RemoteAlert.alerts(from: status(minutes: 300), to: status(minutes: 90)) == [.batteryRunsOut(minutesLeft: 90)])
        #expect(RemoteAlert.alerts(from: status(minutes: 90), to: status(minutes: 80)).isEmpty)
    }

    @Test func silenceAlertsOnlyWhileASessionRan() {
        #expect(RemoteAlert.alerts(from: status(), to: nil) == [.unreachable])
        #expect(RemoteAlert.alerts(from: status(session: false), to: nil).isEmpty)
        #expect(RemoteAlert.alerts(from: .some(nil), to: nil).isEmpty)
    }
}

