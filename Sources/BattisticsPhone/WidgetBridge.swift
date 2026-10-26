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
    /// Activity updates still running, which a background task awaits before it completes.
    private static var changes: [Task<Void, Never>] = []

    static func settle() async {
        // Changes made while waiting are awaited too.
        while let change = changes.first {
            await change.value
            changes.removeAll { $0 == change }
        }
    }

    static func publish(_ mac: MacStore.Mac?, reading: MacStore.Reading?) {
        guard let mac else {
            SharedSnapshot.clear()
            reloadWidgets()
            endActivities()
            return
        }
        let snapshot = SharedSnapshot(mac, reading: reading)
        if snapshot != SharedSnapshot.load() {
            snapshot.save()
            reloadWidgets()
        }
        syncActivity(mac, reading: reading)
    }

    static func publishAll(_ snapshots: [SharedSnapshot]) {
        guard snapshots != SharedSnapshot.loadAll() else { return }
        SharedSnapshot.saveAll(snapshots)
        // A widget set to one Mac reads it from here too.
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    private static func syncActivity(_ mac: MacStore.Mac, reading: MacStore.Reading?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One activity, for the selected Mac.
        for activity in Activity<KeepAwakeActivityAttributes>.activities where activity.attributes.macID != mac.id {
            let id = activity.id
            changes.append(Task { await end(id) })
        }
        guard let status = reading?.status, let session = status.session else {
            // Only a Mac that is answering can tell us its session ended.
            if reading?.reachable == true { endActivities() }
            return
        }
        if let deadline = session.deadline, deadline <= .now {
            endActivities()
            return
        }
        let reachable = reading?.reachable == true
        let current = Activity<KeepAwakeActivityAttributes>.activities
        let existing = current.first(where: { $0.attributes.macID == mac.id })
        // Never start a new activity for a Mac that has gone silent.
        if !reachable && existing == nil { return }

        let state = KeepAwakeActivityAttributes.ContentState(
            mode: session.mode,
            startedAt: session.startedAt,
            deadline: session.deadline,
            batteryPercent: status.battery?.percent,
            isCharging: status.battery?.isCharging ?? false,
            onAdapter: status.battery?.onAdapter ?? false,
            lowPowerMode: status.battery?.lowPowerMode ?? false,
            watts: status.battery?.watts,
            lidClosed: status.lidClosed,
            network: status.network,
            networkName: status.resolvedNetworkName(),
            lastUpdate: status.readAt,
            offline: !reachable
        )
        // Marks the activity stale even if the app never runs again, late
        // enough that throttled pushes alone do not trigger it.
        let content = ActivityContent(state: state, staleDate: status.unheardDate)
        if let activity = existing {
            let id = activity.id
            if activity.content.state != state { changes.append(Task { await update(id, content) }) }
            endActivities(except: id)
        } else {
            endActivities()
            _ = try? Activity.request(attributes: KeepAwakeActivityAttributes(macName: mac.name, macID: mac.id), content: content)
        }
    }

    private static func endActivities(except kept: String? = nil) {
        for id in Activity<KeepAwakeActivityAttributes>.activities.map(\.id) where id != kept {
            changes.append(Task { await end(id) })
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

extension SharedSnapshot {
    init(_ mac: MacStore.Mac, reading: MacStore.Reading?) {
        self.init(macName: mac.name, status: reading?.status, reachable: reading?.reachable ?? false, macID: mac.id)
    }
}
