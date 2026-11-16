import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Companion version compatibility")
struct RemoteCompatibilityTests {
    @Test func versionsCompareNumericallyAndUnknownVersionsStayUnknown() {
        let app = RemoteAppInfo(version: "1.10.0", build: "2", minimumPeerVersion: "1.1.0")
        #expect(app.needsUpdate(for: "1.6.0") == false)
        #expect(app.needsUpdate(for: "2.0.0") == true)
        #expect(app.needsUpdate(for: "1.10.0") == false)
        #expect(RemoteAppInfo(version: "unknown", build: "2", minimumPeerVersion: "1.1.0").needsUpdate(for: "1.6.0") == nil)
        #expect(app.needsUpdate(for: "1.6") == nil)
    }

    @Test func legacyStatusDecodesWithoutVersionAndNewMetadataRoundTrips() throws {
        let old = RemoteStatus(machineName: "Mac", readAt: .now)
        #expect(try RemoteWire.decode(RemoteStatus.self, from: RemoteWire.encode(old)).appInfo == nil)
        var new = old
        new.appInfo = .init(version: "1.6.1", build: "52", minimumPeerVersion: "1.1.0")
        #expect(new.differsNoticeably(from: old))
        #expect(try RemoteWire.decode(RemoteStatus.self, from: RemoteWire.encode(new)).appInfo == new.appInfo)
    }

    @Test func rosterRetainsIndependentPhonesAndRejectsOlderOrInvalidReports() {
        let now = Date.now
        let app = RemoteAppInfo(version: "1.1.0", build: "18", minimumPeerVersion: "1.6.0")
        let first = RemotePhoneInfo(id: UUID().uuidString, name: "Phone A", app: app, seenAt: now)
        var registry = RemotePhoneRegistry()
        registry.record(first, at: now)
        registry.record(.init(id: first.id, name: "Older name", app: app, seenAt: now.addingTimeInterval(-1)), at: now)
        registry.record(.init(id: UUID().uuidString, name: "Phone B", app: app, seenAt: now), at: now)
        registry.record(.init(id: "not-a-device-id", name: "Invalid", app: app, seenAt: now), at: now)
        registry.record(.init(id: UUID().uuidString, name: "Future", app: app, seenAt: now.addingTimeInterval(301)), at: now)
        #expect(registry.phones.count == 2)
        #expect(registry.phones.contains(first))
    }

    @Test func rosterIsBoundedAndExpiresOldReports() {
        let now = Date.now
        let app = RemoteAppInfo(version: "1.1.0", build: "18", minimumPeerVersion: "1.6.0")
        var registry = RemotePhoneRegistry()
        for index in 0..<12 {
            registry.record(.init(id: UUID().uuidString, name: "Phone \(index)", app: app, seenAt: now.addingTimeInterval(Double(index))), at: now)
        }
        #expect(registry.phones.count == 8)
        #expect(registry.phones.first?.name == "Phone 11")
        registry.record(.init(id: UUID().uuidString, name: "New phone", app: app, seenAt: now.addingTimeInterval(31 * 86400)), at: now.addingTimeInterval(31 * 86400))
        #expect(registry.phones.map(\.name) == ["New phone"])
    }
}
