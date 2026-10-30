import ActivityKit
import BattisticsRemote
import Foundation
import UIKit
import WidgetKit

/// Hands the Macs' readings to the widgets and keeps a lock-screen countdown
/// for each Mac kept awake. Without push, both update when the app or its
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
            if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
            return
        }
        let snapshot = SharedSnapshot(mac, reading: reading)
        let saved = SharedSnapshot.load()
        guard snapshot != saved else { return }
        // Saved every time, so any reload shows the newest reading.
        snapshot.save()
        if saved.map(snapshot.differsNoticeably) ?? true || reloadDue {
            reloadWidgets()
            if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        }
    }

    /// One countdown per Mac, so picking another Mac in the app leaves a
    /// running one on the Lock Screen.
    /// `confirmed` is false before this launch's first read, when a saved
    /// reading too old to be live says nothing about the Mac.
    static func syncActivities(_ macs: [(mac: MacStore.Mac, reading: MacStore.Reading?)], confirmed: Bool) {
        let ids = Set(macs.map(\.mac.id))
        // A Mac that stopped sharing takes its countdown with it.
        for activity in Activity<KeepAwakeActivityAttributes>.activities where !ids.contains(activity.attributes.macID) {
            let id = activity.id
            changes.append(Task { await end(id) })
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for (mac, reading) in macs {
            if !confirmed, reading?.reachable != true { continue }
            syncActivity(mac, reading: reading)
        }
    }

    static func publishAll(_ snapshots: [SharedSnapshot]) {
        let saved = SharedSnapshot.loadAll()
        guard snapshots != saved else { return }
        SharedSnapshot.saveAll(snapshots)
        // A widget set to one Mac reads it from here too.
        if snapshots.count != saved.count || zip(snapshots, saved).contains(where: { $0.differsNoticeably(from: $1) })
            || reloadDue {
            reloadWidgets()
        }
    }

    /// Each reload in the background spends WidgetKit's daily budget, so
    /// widgets reload for what they show, and otherwise only well before the
    /// reading they hold is old enough to call the Mac unheard.
    private static var lastReload = Date.distantPast

    private static var reloadDue: Bool { -lastReload.timeIntervalSinceNow > RemoteStatus.unheardDelay / 2 }

    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        lastReload = .now
    }

    private static func syncActivity(_ mac: MacStore.Mac, reading: MacStore.Reading?) {
        // Asleep, silent, or finished: the lock-screen countdown has to leave.
        // A fetch is what decides silence, so a missed push alone does not.
        guard reading?.reachable == true, reading?.status?.sleptAt == nil,
              let status = reading?.status, let session = status.session,
              session.isActive(at: .now) else {
            endActivities(of: mac.id)
            return
        }
        let existing = Activity<KeepAwakeActivityAttributes>.activities.first { $0.attributes.macID == mac.id }

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
            lastUpdate: status.readAt
        )
        // Marks the activity stale even if the app never runs again, late
        // enough that throttled pushes alone do not trigger it.
        let content = ActivityContent(state: state, staleDate: status.unheardDate)
        if let activity = existing {
            let id = activity.id
            if activity.content.state != state { changes.append(Task { await update(id, content) }) }
            endActivities(of: mac.id, except: id)
        } else {
            _ = try? Activity.request(attributes: KeepAwakeActivityAttributes(macName: mac.name, macID: mac.id), content: content)
        }
    }

    private static func endActivities(of macID: String, except kept: String? = nil) {
        for activity in Activity<KeepAwakeActivityAttributes>.activities
        where activity.attributes.macID == macID && activity.id != kept {
            let id = activity.id
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
