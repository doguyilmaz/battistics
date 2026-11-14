import ActivityKit
import BattisticsRemote
import UserNotifications
import XCTest
@testable import Battistics_Remote

final class NotificationsTests: XCTestCase {
    @MainActor
    func testQueuedStopAndRestartKeepsTheNewActivity() async throws {
        let now = Date()
        let mac = MacStore.Mac(id: "activity-restart-test", name: "Test Mac")
        var status = RemoteStatus(machineName: mac.name, readAt: now,
                                  session: .init(mode: .displayMaySleep, origin: .phone,
                                                 startedAt: now.addingTimeInterval(-3600), deadline: nil),
                                  heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: true))], confirmed: true)
        await WidgetBridge.settle()
        let original = try XCTUnwrap(Activity<KeepAwakeActivityAttributes>.activities.first { $0.attributes.macID == mac.id })

        status.session = nil
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: true))], confirmed: true)
        status.readAt = now.addingTimeInterval(1)
        status.session = .init(mode: .displayOn, origin: .phone, startedAt: now, deadline: nil)
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: true))], confirmed: true)
        status.readAt = now.addingTimeInterval(2)
        status.session?.deadline = now.addingTimeInterval(3600)
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: true))], confirmed: true)
        await WidgetBridge.settle()

        let activities = Activity<KeepAwakeActivityAttributes>.activities.filter { $0.attributes.macID == mac.id }
        XCTAssertEqual(activities.count, 1)
        let restarted = try XCTUnwrap(activities.first)
        let content = try await Self.content(of: restarted.id, updatedAt: status.readAt)
        XCTAssertNotEqual(restarted.id, original.id)
        XCTAssertEqual(content.startedAt, now)
        XCTAssertEqual(content.lastUpdate, status.readAt)
        XCTAssertEqual(content.deadline, status.session?.deadline)

        WidgetBridge.syncActivities([], confirmed: true)
        await WidgetBridge.settle()
    }

    @MainActor
    func testAnEndedActivityIsReplacedForAnOngoingSession() async throws {
        let now = Date()
        let mac = MacStore.Mac(id: "activity-ended-test", name: "Test Mac")
        let status = RemoteStatus(machineName: mac.name, readAt: now,
                                  session: .init(mode: .displayMaySleep, origin: .phone,
                                                 startedAt: now.addingTimeInterval(-9 * 3600), deadline: nil),
                                  heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: true))], confirmed: true)
        await WidgetBridge.settle()
        let original = try XCTUnwrap(Activity<KeepAwakeActivityAttributes>.activities.first { $0.attributes.macID == mac.id })
        await Self.endRetainingActivity(original.id, until: now.addingTimeInterval(3600))
        XCTAssertEqual(original.activityState, .ended)

        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: true))], confirmed: true)
        await WidgetBridge.settle()
        let replacement = try XCTUnwrap(Activity<KeepAwakeActivityAttributes>.activities.first {
            $0.attributes.macID == mac.id && ($0.activityState == .active || $0.activityState == .stale)
        })
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.content.state.startedAt, status.session?.startedAt)

        WidgetBridge.syncActivities([], confirmed: true)
        await WidgetBridge.settle()
    }

    private nonisolated static func endRetainingActivity(_ id: String, until date: Date) async {
        await Activity<KeepAwakeActivityAttributes>.activities.first { $0.id == id }?
            .end(nil, dismissalPolicy: .after(date))
    }

    /// ActivityKit propagates updates asynchronously, even after update returns.
    private nonisolated static func content(of id: String, updatedAt date: Date) async throws -> KeepAwakeActivityAttributes.ContentState {
        try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(5))) {
            let activity = try XCTUnwrap(Activity<KeepAwakeActivityAttributes>.activities.first { $0.id == id })
            if activity.content.state.lastUpdate >= date { return activity.content.state }
            for await content in activity.contentUpdates where content.state.lastUpdate >= date {
                return content.state
            }
            throw CancellationError()
        }
    }

    @MainActor
    func testOldTelemetryKeepsAStaleActivityUntilAnExplicitEnd() async throws {
        let now = Date()
        let mac = MacStore.Mac(id: "stale-activity-test", name: "Test Mac")
        var status = RemoteStatus(machineName: mac.name, readAt: now.addingTimeInterval(-2100),
                                  session: .init(mode: .displayMaySleep, origin: .ai,
                                                 startedAt: now.addingTimeInterval(-3600), deadline: nil),
                                  heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        XCTAssertTrue(ActivityAuthorizationInfo().areActivitiesEnabled)
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: false))], confirmed: true)
        await WidgetBridge.settle()
        let activity = try XCTUnwrap(Activity<KeepAwakeActivityAttributes>.activities.first { $0.attributes.macID == mac.id })
        XCTAssertLessThan(try XCTUnwrap(activity.content.staleDate), now)
        XCTAssertEqual(activity.content.state.startedAt, status.session?.startedAt)

        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: false))], confirmed: true)
        await WidgetBridge.settle()
        XCTAssertTrue(Activity<KeepAwakeActivityAttributes>.activities.contains { $0.id == activity.id })

        status.sleptAt = now
        WidgetBridge.syncActivities([(mac, .init(status: status, reachable: false))], confirmed: true)
        await WidgetBridge.settle()
        XCTAssertFalse(Activity<KeepAwakeActivityAttributes>.activities.contains { $0.id == activity.id })
    }

    @MainActor
    func testSchedulingUpgradeAndOfflineSwitchOff() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        XCTAssertTrue(granted, "The simulator must grant notification permission to exercise real scheduling")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Notifications.enabledKey)
        defaults.set(true, forKey: Notifications.enabledKey)
        Notifications.cancelAll()
        defer {
            Notifications.cancelAll()
            if let previous { defaults.set(previous, forKey: Notifications.enabledKey) }
            else { defaults.removeObject(forKey: Notifications.enabledKey) }
        }

        let now = Date()
        let mac = MacStore.Mac(id: "notification-test", name: "Test Mac")
        var status = RemoteStatus(machineName: mac.name, readAt: now,
                                  session: .init(mode: .displayMaySleep, origin: .phone, startedAt: now, deadline: nil),
                                  heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        await Notifications.syncReminders(for: mac, reading: .init(status: status, reachable: true))
        var pending = await center.pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty, "An indefinite background task must not schedule silence notifications")
        // A queued observation must be rechecked after any awaited UI work.
        let freshMac = try XCTUnwrap(MacStore.shared.macs.first)
        await Notifications.deliver([(freshMac, [.unreachable]), (mac, [.unreachable])])
        let resolvedAlerts = await center.deliveredNotifications()
        XCTAssertFalse(resolvedAlerts.contains { $0.request.identifier.hasSuffix(".silent") })

        status.session?.deadline = now.addingTimeInterval(3600)
        await Notifications.syncReminders(for: mac, reading: .init(status: status, reachable: true))
        pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.map(\.identifier), ["notification-test.ending"])

        status.session?.origin = .ai
        await Notifications.syncReminders(for: mac, reading: .init(status: status, reachable: true))
        pending = await center.pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty, "Automatic task leases must not produce deadline reminders")

        let content = UNMutableNotificationContent()
        content.body = "Legacy notification"
        for id in ["old-mac.silent", "old-mac.quiet", "old-mac.ending"] {
            try await center.add(.init(identifier: id, content: content,
                                       trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
        }
        await Notifications.removeLegacySilenceReminders()
        pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.map(\.identifier), ["old-mac.ending"], "Upgrade must remove obsolete timers even for a forgotten Mac")

        // No cloud call or subsequent reading is needed to apply switch-off.
        defaults.set(false, forKey: Notifications.enabledKey)
        Notifications.cancelAll()
        status.session?.origin = .phone
        await Notifications.syncReminders(for: mac, reading: .init(status: status, reachable: true))
        pending = await center.pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty)
        let delivered = await center.deliveredNotifications()
        XCTAssertTrue(delivered.isEmpty)
    }
}
