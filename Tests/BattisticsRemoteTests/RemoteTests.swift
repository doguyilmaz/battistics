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
        let lpmRequest = RemoteRequest(operation: .setLowPower, lowPowerPolicy: .onlyOnBattery, deviceName: "iPhone",
                                       sentAt: Date(timeIntervalSince1970: 1_000_000))
        #expect(try RemoteWire.decode(RemoteRequest.self, from: RemoteWire.encode(lpmRequest)) == lpmRequest)
        let sleepRequest = RemoteRequest(operation: .sleepDisplay, deviceName: "iPhone",
                                         sentAt: Date(timeIntervalSince1970: 1_000_000))
        #expect(try RemoteWire.decode(RemoteRequest.self, from: RemoteWire.encode(sleepRequest)) == sleepRequest)
        #expect(throws: (any Error).self) { try RemoteWire.decode(RemoteRequest.self, from: Data("{}".utf8)) }
    }

    @Test func chargeRateNeedsAQuarterHourOfRecentReadings() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let point = { (minutesAgo: Double, percent: Double) in RemoteStatus.ChargePoint(at: now.addingTimeInterval(-minutesAgo * 60), percent: percent) }
        #expect(ChargeRate.perHour([point(10, 50), point(0, 48)], now: now) == nil)
        #expect(ChargeRate.perHour([point(200, 90), point(60, 60), point(0, 50)], now: now) == -10)
        #expect(ChargeRate.perHour([point(30, 40), point(0, 52)], now: now) == 24)
        #expect(ChargeRate.perHour([point(60, 50), point(0, 50.5)], now: now) == nil)
        #expect(ChargeRate.minutesLeft(percent: 50, rate: -10) == 300)
        #expect(ChargeRate.minutesLeft(percent: 76, rate: 24) == 60)
        let day = [point(600, 80), point(400, 40), point(300, 90), point(0, 70)]
        #expect(ChargeRate.totals(day) == (gained: 50, used: 60))
        #expect(ChargeRate.totals([point(0, 50)]) == (gained: 0, used: 0))
    }

    @Test func anOperationFromANewerPhoneDecodesAsUnknown() throws {
        var json = try JSONSerialization.jsonObject(with: RemoteWire.encode(RemoteRequest(operation: .stop))) as! [String: Any]
        json["operation"] = "hibernate"
        let request = try RemoteWire.decode(RemoteRequest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(request.operation == .unknown)
    }

    @Test func valuesFromANewerMacKeepItsStatusReadable() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var status = RemoteStatus(machineName: "Mac", readAt: now,
                                  session: .init(mode: .displayOn, origin: .manual, startedAt: now, deadline: nil),
                                  lastEnd: .init(reason: .timer, at: now), network: .wifi, thermal: .fair)
        status.lastCommand = .init(id: "c", failure: RemoteFailure(.busy))
        var json = try JSONSerialization.jsonObject(with: RemoteWire.encode(status)) as! [String: Any]
        var session = json["session"] as! [String: Any]
        session["origin"] = "watch"
        json["session"] = session
        json["lastEnd"] = ["reason": "eclipse", "at": 1_000_000]
        json["network"] = "satellite"
        json["thermal"] = "molten"
        json["lastCommand"] = ["id": "c", "failure": ["code": "quota", "message": "Später"]]
        let decoded = try RemoteWire.decode(RemoteStatus.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.session?.origin == .manual)
        #expect(decoded.lastEnd?.reason == .user)
        #expect(decoded.network == .other)
        #expect(decoded.thermal == .nominal)
        #expect(decoded.lastCommand?.failure == RemoteFailure(.startFailed, "Später"))
    }

    @Test func allowedDurationsIncludeUntilTurnedOffAndTelemetryRoundTrips() throws {
        #expect(RemoteRequest.allowedDurations.contains(0))
        #expect(RemoteRequest.allowedDurations == [0, 15, 30, 60, 120, 240, 360, 720])
        let now = Date(timeIntervalSince1970: 1_000_000)
        let status = RemoteStatus(
            machineName: "Mac", readAt: now,
            battery: .init(percent: 82, isCharging: true, onAdapter: true, minutesRemaining: 45,
                           healthPercent: 96, lowPowerMode: true, lowPowerPolicy: .onlyOnBattery,
                           watts: 42.5, adapterWatts: 67, temperatureC: 34.2, cycleCount: 118),
            session: .init(mode: .lidClosed, origin: .phone, name: "Dogu’s iPhone 16e", startedAt: now, deadline: nil),
            network: .hotspot, networkName: "Dogu’s iPhone 16e", lidClosed: true,
            protection: .init(closedLidAllowed: true))
        let decoded = try RemoteWire.decode(RemoteStatus.self, from: RemoteWire.encode(status))
        #expect(decoded == status)
        #expect(decoded.battery?.lowPowerMode == true)
        #expect(decoded.battery?.lowPowerPolicy == .onlyOnBattery)
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

    @Test func sessionUsesTheHeartbeatTheMacPromised() {
        let readAt = Date(timeIntervalSince1970: 1_000_000)
        let session = RemoteStatus.Session(mode: .lidClosed, origin: .phone, startedAt: readAt, deadline: nil)
        let status = RemoteStatus(machineName: "Mac", readAt: readAt, session: session,
                                  heartbeatSeconds: RemoteStatus.heartbeat(duringSession: true))
        #expect(status.heartbeatSeconds == RemoteStatus.sessionHeartbeat)
        #expect(status.staleDate == readAt.addingTimeInterval(RemoteStatus.sessionHeartbeat * 4))
        #expect(status.isFresh(at: readAt.addingTimeInterval(RemoteStatus.sessionHeartbeat * 3)))
        #expect(!status.isFresh(at: status.staleDate))
    }

    @Test func watchdogFollowsHowReliablyPushesArrive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let session = RemoteStatus.Session(mode: .lidClosed, origin: .phone, startedAt: now, deadline: nil)
        let status = RemoteStatus(machineName: "Mac", readAt: now, session: session,
                                  heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        let stale = RemoteStatus.sessionHeartbeat * 4 + 45
        #expect(status.quietDelay == stale)
        let steady = (1...8).map { now.addingTimeInterval(Double(-$0) * 120) }
        #expect(status.watchdogDelay(backgroundDeliveries: steady, now: now) == stale)
        let burst = (1...4).map { now.addingTimeInterval(Double(-$0) * 120) }
        #expect(status.watchdogDelay(backgroundDeliveries: burst, now: now) == RemoteStatus.unheardDelay)
        let throttled = (1...4).map { now.addingTimeInterval(Double(-$0) * 1500) }
        #expect(status.watchdogDelay(backgroundDeliveries: throttled, now: now) == RemoteStatus.unheardDelay)
        let patchy = [-1500, -900, -600, -120].map { now.addingTimeInterval(Double($0)) }
        #expect(status.watchdogDelay(backgroundDeliveries: patchy, now: now) == 900)
        #expect(status.watchdogDelay(backgroundDeliveries: [], now: now) == RemoteStatus.unheardDelay)
    }

    @Test func phoneOnlySurfacesWaitLongerThanAFetch() {
        let readAt = Date(timeIntervalSince1970: 1_000_000)
        let session = RemoteStatus.Session(mode: .lidClosed, origin: .phone, startedAt: readAt, deadline: nil)
        let status = RemoteStatus(machineName: "Mac", readAt: readAt, session: session,
                                  heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        #expect(status.unheardDate == readAt.addingTimeInterval(RemoteStatus.unheardDelay))
        #expect(status.unheardDate > status.staleDate)
        let idle = RemoteStatus(machineName: "Mac", readAt: readAt, heartbeatSeconds: 3600)
        #expect(idle.unheardDate == idle.staleDate)
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

    @Test func chargeTargetAlertsOnceWhileCharging() {
        let below = status(percent: 79, adapter: true, session: false)
        let reached = status(percent: 80, adapter: true, session: false)
        #expect(RemoteAlert.alerts(from: below, to: reached, chargeTarget: 80) == [.chargeReached(percent: 80)])
        #expect(RemoteAlert.alerts(from: reached, to: status(percent: 81, adapter: true, session: false), chargeTarget: 80).isEmpty)
        #expect(RemoteAlert.alerts(from: below, to: reached).isEmpty)
        #expect(RemoteAlert.alerts(from: below, to: status(percent: 80, adapter: false, session: false), chargeTarget: 80).isEmpty)
    }

    @Test func theMacPushesWhatItCanSeeAndLeavesThePhoneItsOwn() {
        #expect(RemoteAlert.pushed(from: status(), to: status(session: false, ended: .timer)) == [.sessionEnded(.timer)])
        #expect(RemoteAlert.pushed(from: status(percent: 21), to: status(percent: 20)) == [.batteryLow(percent: 20)])
        let below = status(percent: 79, adapter: true, session: false)
        #expect(RemoteAlert.pushed(from: below, to: status(percent: 80, adapter: true, session: false)).isEmpty)
        #expect(!RemoteAlert.pushedKinds.contains(RemoteAlert.unreachable.kind))
        #expect(!RemoteAlert.pushedKinds.contains(RemoteAlert.chargeReached(percent: 80).kind))
    }

    @Test func heatAlertsOnceWhenASessionRunsHot() {
        var hot = status()
        hot.thermal = .serious
        #expect(RemoteAlert.alerts(from: status(), to: hot) == [.runningHot])
        var hotter = hot
        hotter.thermal = .critical
        #expect(RemoteAlert.alerts(from: hot, to: hotter).isEmpty)
        var idleHot = status(session: false)
        idleHot.thermal = .critical
        #expect(RemoteAlert.alerts(from: status(session: false), to: idleHot).isEmpty)
        #expect(RemoteAlert.pushed(from: status(), to: hot) == [.runningHot])
    }

    @Test func silenceAlertsOnlyWhileASessionRan() {
        #expect(RemoteAlert.alerts(from: status(), to: nil) == [.unreachable])
        #expect(RemoteAlert.alerts(from: status(session: false), to: nil).isEmpty)
        #expect(RemoteAlert.alerts(from: .some(nil), to: nil).isEmpty)
    }

    @Test func unplugOrClosingLidOnWiFiDuringSessionAlertsForHotspot() {
        var pluggedWiFi = status(percent: 80, adapter: true, session: true)
        pluggedWiFi.network = .wifi
        pluggedWiFi.lidClosed = false

        var unpluggedWiFi = status(percent: 80, adapter: false, session: true)
        unpluggedWiFi.network = .wifi
        unpluggedWiFi.lidClosed = false
        #expect(RemoteAlert.alerts(from: pluggedWiFi, to: unpluggedWiFi) == [.unpluggedWithoutHotspot])

        var closedOnWiFi = unpluggedWiFi
        closedOnWiFi.lidClosed = true
        #expect(RemoteAlert.alerts(from: unpluggedWiFi, to: closedOnWiFi) == [.closedLidWithoutHotspot])

        var lowAndClosed = unpluggedWiFi
        lowAndClosed.lidClosed = true
        lowAndClosed.battery?.percent = 18
        #expect(RemoteAlert.alerts(from: unpluggedWiFi, to: lowAndClosed) == [.batteryLow(percent: 18), .closedLidWithoutHotspot])

        var unpluggedHotspot = unpluggedWiFi
        unpluggedHotspot.network = .hotspot
        #expect(RemoteAlert.alerts(from: pluggedWiFi, to: unpluggedHotspot).isEmpty)
    }
}

