import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Remote companion contract")
struct RemoteTests {
    @Test func pairingSurvivesItsURLAndRejectsTampering() throws {
        let pairing = RemotePairing(name: "Doğu’s MacBook Pro", host: "100.101.102.103", port: 47_616,
                                    token: RemotePairing.makeToken())
        #expect(RemotePairing(url: pairing.url) == pairing)
        var short = URLComponents(url: pairing.url, resolvingAgainstBaseURL: false)!
        short.queryItems = short.queryItems!.map { $0.name == "t" ? .init(name: "t", value: "abc") : $0 }
        #expect(RemotePairing(url: short.url!) == nil)
        var badHost = URLComponents(url: pairing.url, resolvingAgainstBaseURL: false)!
        badHost.queryItems = badHost.queryItems!.map { $0.name == "h" ? .init(name: "h", value: "a b/c") : $0 }
        #expect(RemotePairing(url: badHost.url!) == nil)
        #expect(RemotePairing(url: URL(string: "https://pair?n=x")!) == nil)
    }

    @Test func tokensAreUniqueAndOnlyTheirHashMatches() {
        let token = RemotePairing.makeToken(), other = RemotePairing.makeToken()
        #expect(token != other && token.count == 43)
        let hash = RemotePairing.hash(token)
        #expect(RemotePairing.matches(token, hash: hash))
        #expect(!RemotePairing.matches(other, hash: hash))
        #expect(!RemotePairing.matches(token, hash: String(hash.dropLast())))
    }

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
        let request = RemoteRequest(token: RemotePairing.makeToken(), operation: .start,
                                    mode: .displayMaySleep, durationMinutes: 60, deviceName: "iPhone")
        let data = try RemoteWire.encode(request)
        #expect(data.last == 10)
        #expect(try RemoteWire.decode(RemoteRequest.self, from: data) == request)
        #expect(throws: (any Error).self) { try RemoteWire.decode(RemoteRequest.self, from: Data("{}\n".utf8)) }
    }

    @Test func serverAnswersOnlyOnItsAddressAndLimitsFailedAttempts() async throws {
        let port = UInt16.random(in: 50_000...60_000)
        let token = RemotePairing.makeToken(), hash = RemotePairing.hash(token)
        let server = RemoteServer(port: port) { request in
            guard RemotePairing.matches(request.token, hash: hash) else { return .init(.unauthorized, "Pair again.") }
            return .init(status: .init(machineName: "Test Mac", readAt: Date()))
        }
        let listening = await server.listen(on: ["127.0.0.1"])
        #expect(listening == ["127.0.0.1"])
        let good = RemotePairing(name: "Test Mac", host: "127.0.0.1", port: port, token: token)
        let reply = try await RemoteClient.send(.init(token: token, operation: .status), to: good)
        #expect(reply.status?.machineName == "Test Mac")

        let wrong = RemotePairing(name: "Test Mac", host: "127.0.0.1", port: port, token: RemotePairing.makeToken())
        for _ in 0..<5 {
            let denied = try await RemoteClient.send(.init(token: wrong.token, operation: .status), to: wrong)
            #expect(denied.error?.code == .unauthorized)
        }
        let limited = try await RemoteClient.send(.init(token: token, operation: .status), to: good)
        #expect(limited.error?.code == .rateLimited)

        await server.stop()
        await #expect(throws: (any Error).self) {
            try await RemoteClient.send(.init(token: token, operation: .status), to: good, timeout: .seconds(2))
        }
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

@Suite("Pairing hosts")
struct PairingHostTests {
    @Test func onlyTailscaleAddressesAreTrusted() {
        func pairing(_ host: String) -> RemotePairing { .init(name: "Mac", host: host, port: 1, token: "t") }
        #expect(pairing("100.64.0.1").isTailscaleHost)
        #expect(pairing("100.127.255.254").isTailscaleHost)
        #expect(pairing("mac.tail1234.ts.net").isTailscaleHost)
        #expect(!pairing("100.128.0.1").isTailscaleHost)
        #expect(!pairing("192.168.1.10").isTailscaleHost)
        #expect(!pairing("127.0.0.1").isTailscaleHost)
        #expect(!pairing("evil.example.com").isTailscaleHost)
    }
}
