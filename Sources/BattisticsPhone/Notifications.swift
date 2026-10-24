import BackgroundTasks
import BattisticsRemote
import UIKit
import UserNotifications

/// Local notifications from background refresh: no server, no cost. iOS
/// decides when refresh runs, so these are best effort.
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
                await deliver(MacStore.shared.refreshAll())
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
}

private extension RemoteAlert {
    var kind: String {
        switch self {
        case .sessionEnded: "ended"
        case .batteryLow: "battery"
        case .batteryRunsOut: "runtime"
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
        case .unreachable:
            String(localized: "Stopped answering while Keep Awake was on. It may be offline or asleep.")
        }
    }
}
