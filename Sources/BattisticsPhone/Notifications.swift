import BackgroundTasks
import BattisticsRemote
import UIKit
import UserNotifications

/// Local notifications from background refresh and a rolling local watchdog
/// timer when Keep Awake is active: no third-party server, no cost.
enum Notifications {
    static let enabledKey = "notificationsEnabled"
    static let refreshTask = "com.doguyilmaz.Battistics.Remote.refresh"

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTask, using: nil) { task in
            // BGTask is thread-safe but not marked Sendable.
            nonisolated(unsafe) let refresh = task
            schedule()
            let work = Task { @MainActor in
                LocalPhoneMonitor.shared.refresh()
                _ = await MacStore.shared.refreshAll()
                refresh.setTaskCompleted(success: !Task.isCancelled)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func deliver(_ results: [(MacStore.Mac, [RemoteAlert])]) async {
        guard UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true else { return }
        for (mac, alerts) in results {
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = mac.name
                content.body = alert.message
                content.sound = .default
                let request = UNNotificationRequest(identifier: "\(mac.id).\(alert.kind)", content: content, trigger: nil)
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }

    /// Maintains a rolling local notification while a Keep Awake session is
    /// active, for a Mac that goes quiet while the app is suspended. Each
    /// fresh reading pushes it forward and clears one already delivered; how
    /// far ahead depends on how reliably pushes reach this phone right now.
    @MainActor
    static func syncWatchdog(for mac: MacStore.Mac, reading: MacStore.Reading?) {
        // Shares the `.unreachable` alert identifier, so a foreground refresh
        // and the background timer replace each other instead of stacking.
        let id = "\(mac.id).silent"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let reading, reading.reachable else { return }
        // The Mac is answering again: an earlier "stopped answering" alert is now wrong.
        center.removeDeliveredNotifications(withIdentifiers: [id])
        // On Hotspot the lid and unplug warnings no longer apply.
        if reading.status?.network == .hotspot {
            center.removeDeliveredNotifications(withIdentifiers: ["\(mac.id).closedlid", "\(mac.id).unplugged"])
        }

        guard UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true,
              let status = reading.status,
              let session = status.session else {
            return
        }

        let fireAt = status.readAt.addingTimeInterval(DeliveryCadence.watchdogDelay(for: status))
        if let deadline = session.deadline, deadline <= fireAt { return }
        let delay = max(60, fireAt.timeIntervalSinceNow)

        let lastSeen = status.readAt.formatted(date: .omitted, time: .shortened)
        let content = UNMutableNotificationContent()
        content.title = mac.name
        if status.network == .hotspot {
            content.body = String(localized: "No word from the Mac since \(lastSeen) during Keep Awake. It may be out of Personal Hotspot range.")
        } else if session.mode == .lidClosed || status.battery?.onAdapter == false {
            content.body = String(localized: "No word from the Mac since \(lastSeen) during Keep Awake. If it left Wi‑Fi, turn on Personal Hotspot so it can reconnect.")
        } else {
            content.body = String(localized: "No word from the Mac since \(lastSeen) during Keep Awake. Open Battistics to check it.")
        }
        content.sound = .default
        content.threadIdentifier = mac.id

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Remembers when background pushes actually reached this phone, for
/// `RemoteStatus.watchdogDelay`.
enum DeliveryCadence {
    private static let key = "backgroundDeliveries"
    private static let window: TimeInterval = 90 * 60

    /// Called for every background wake that fetched the Mac's status.
    static func recordBackgroundDelivery(at date: Date = .now) {
        let recent = deliveries().filter { date.timeIntervalSince($0) < window }
        UserDefaults.standard.set((recent + [date]).suffix(16).map(\.timeIntervalSince1970), forKey: key)
    }

    static func watchdogDelay(for status: RemoteStatus, now: Date = .now) -> TimeInterval {
        status.watchdogDelay(backgroundDeliveries: deliveries().filter { now.timeIntervalSince($0) < window }, now: now)
    }

    private static func deliveries() -> [Date] {
        (UserDefaults.standard.array(forKey: key) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }
}

private extension RemoteAlert {
    var kind: String {
        switch self {
        case .sessionEnded: "ended"
        case .batteryLow: "battery"
        case .batteryRunsOut: "runtime"
        case .unpluggedWithoutHotspot: "unplugged"
        case .closedLidWithoutHotspot: "closedlid"
        case .unreachable: "silent"
        }
    }

    var message: String {
        switch self {
        case .sessionEnded(let reason):
            if let reason { String(localized: "Keep Awake ended: \(reason.label).") }
            else { String(localized: "Keep Awake ended.") }
        case .batteryLow(let percent):
            String(localized: "Battery is at \(percent)%. Connect power if the Mac must keep running.")
        case .batteryRunsOut(let minutes):
            String(localized: "The battery lasts about \(DurationLabel.long(minutes: minutes)), less than the Keep Awake session.")
        case .unpluggedWithoutHotspot:
            String(localized: "Unplugged on Wi‑Fi while Keep Awake is active. Turn on Personal Hotspot before putting your Mac in a bag so your tasks stay online.")
        case .closedLidWithoutHotspot:
            String(localized: "Lid closed on battery without Hotspot. Connect to Personal Hotspot if you are taking your Mac with you.")
        case .unreachable:
            String(localized: "Stopped answering while Keep Awake was on. Connect to Personal Hotspot or check Wi‑Fi if a task is running.")
        }
    }
}
