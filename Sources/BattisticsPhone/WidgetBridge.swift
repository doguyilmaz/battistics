import ActivityKit
import BattisticsRemote
import Foundation
import UIKit
import WidgetKit

/// Hands the selected Mac's reading to the widgets and keeps the lock-screen
/// countdown in step with it. Without push, both update when the app or its
/// background refresh runs; the countdown itself runs on the system clock.
@MainActor
enum WidgetBridge {
    static func publish(_ mac: MacStore.Mac?, reading: MacStore.Reading?) {
        guard let mac else {
            SharedSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
            endActivities()
            return
        }
        var adjustedStatus = reading?.status
        if adjustedStatus?.network == .hotspot, adjustedStatus?.networkName == nil {
            adjustedStatus?.networkName = UIDevice.current.name
        }
        let snapshot = SharedSnapshot(macName: mac.name, status: adjustedStatus,
                                      lastSeen: reading?.lastSeen, reachable: reading?.reachable ?? false)
        if snapshot != SharedSnapshot.load() {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        syncActivity(mac, reading: reading)
    }

    private static func syncActivity(_ mac: MacStore.Mac, reading: MacStore.Reading?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A silent Mac keeps its countdown; it ends on its own at the deadline.
        guard reading?.reachable == true else { return }
        guard let status = reading?.status, let session = status.session else {
            endActivities()
            return
        }
        if let deadline = session.deadline, deadline <= .now {
            endActivities()
            return
        }
        let state = KeepAwakeActivityAttributes.ContentState(
            mode: session.mode,
            startedAt: session.startedAt,
            deadline: session.deadline,
            sessionName: session.name ?? session.origin.label,
            batteryPercent: status.battery?.percent,
            isCharging: status.battery?.isCharging ?? false,
            onAdapter: status.battery?.onAdapter ?? false,
            lowPowerMode: status.battery?.lowPowerMode ?? false,
            watts: status.battery?.watts,
            lidClosed: status.lidClosed,
            network: status.network,
            networkName: status.resolvedNetworkName(fallbackHotspot: UIDevice.current.name)
        )
        let content = ActivityContent(state: state, staleDate: session.deadline)
        let current = Activity<KeepAwakeActivityAttributes>.activities
        if let activity = current.first(where: { $0.attributes.macName == mac.name }) {
            let id = activity.id
            if activity.content.state != state { Task { await update(id, content) } }
            endActivities(except: id)
        } else {
            endActivities()
            _ = try? Activity.request(attributes: KeepAwakeActivityAttributes(macName: mac.name), content: content)
        }
    }

    private static func endActivities(except kept: String? = nil) {
        for id in Activity<KeepAwakeActivityAttributes>.activities.map(\.id) where id != kept {
            Task { await end(id) }
        }
    }

    /// Looked up by id off the main actor, since `Activity` is not Sendable.
    private nonisolated static func update(_ id: String, _ content: ActivityContent<KeepAwakeActivityAttributes.ContentState>) async {
        await Activity<KeepAwakeActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func end(_ id: String) async {
        await Activity<KeepAwakeActivityAttributes>.activities.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate)
    }
}
