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

    /// Maintains a rolling local timer notification while a Keep Awake session
    /// is active. Each fresh CloudKit reading pushes the timer forward; if the
    /// Mac loses internet (for example, in a bag after leaving Wi-Fi without
    /// Personal Hotspot), the timer fires even if the app is suspended.
    @MainActor
    static func syncWatchdog(for mac: MacStore.Mac, reading: MacStore.Reading?) {
        let id = "\(mac.id).watchdog"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true,
              let reading, reading.reachable,
              let status = reading.status,
              let session = status.session else {
            return
        }

        let isMobileRisk = session.mode == .lidClosed || status.battery?.onAdapter == false
        let delay: TimeInterval = (isMobileRisk && status.network != .hotspot) ? 10 * 60 : 18 * 60
        if let deadline = session.deadline, deadline.timeIntervalSinceNow <= delay {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = mac.name
        content.body = status.network == .hotspot
            ? String(localized: "No response during Keep Awake. Check if your Mac is still within Personal Hotspot range.")
            : String(localized: "Connection lost while Keep Awake was running. If you have an active task on your Mac, turn on Personal Hotspot or check Wi‑Fi.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
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
