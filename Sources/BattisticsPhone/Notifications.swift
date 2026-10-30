import BackgroundTasks
import BattisticsRemote
import UIKit
import UserNotifications

/// Local notifications from background refresh and a rolling local watchdog
/// timer when Keep Awake is active: no third-party server, no cost.
enum Notifications {
    static let enabledKey = "notificationsEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    /// Whether iCloud shows the Mac's own alerts on this phone, so the app does not repeat them.
    static let pushedKey = "alertPushesSubscribed"
    /// Charge level to report while a Mac charges; 0 is off.
    static let chargeTargetKey = "chargeAlertPercent"

    static var chargeTarget: Int? {
        let value = UserDefaults.standard.integer(forKey: chargeTargetKey)
        return value > 0 ? value : nil
    }
    /// Macs already reported at the charge target during this charge.
    private static let chargedKey = "chargeAlerted"

    static func latchCharge(_ alerts: [RemoteAlert], macID: String, status: RemoteStatus?) -> [RemoteAlert] {
        var latched = Set(UserDefaults.standard.stringArray(forKey: chargedKey) ?? [])
        if let status, status.battery?.onAdapter == false
            || chargeTarget.map({ RemoteAlert.chargeAlertRearms(at: status, target: $0) }) == true {
            latched.remove(macID)
        }
        var alerts = alerts
        if alerts.contains(where: { $0.kind == .charged }) {
            if latched.contains(macID) { alerts.removeAll { $0.kind == .charged } } else { latched.insert(macID) }
        }
        UserDefaults.standard.set(Array(latched), forKey: chargedKey)
        return alerts
    }

    static let refreshTask = "com.doguyilmaz.Battistics.Remote.refresh"
    static let extendAction = "extend30"
    private static let endingCategory = "keepawake.ending"
    private static let endingLead: TimeInterval = 5 * 60

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func register() {
        let extend = UNNotificationAction(identifier: extendAction, title: String(localized: "Add 30 Minutes"))
        UNUserNotificationCenter.current().setNotificationCategories(AlertActions.categories.union([
            UNNotificationCategory(identifier: endingCategory, actions: [extend], intentIdentifiers: []),
        ]))
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
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        for (mac, alerts) in results {
            for alert in alerts {
                let id = "\(mac.id).\(alert.kind.rawValue)"
                // The watchdog already said so under this identifier; adding it again sounds twice.
                if alert == .unreachable, delivered.contains(id) { continue }
                let content = UNMutableNotificationContent()
                content.title = mac.name
                content.body = alert.message
                content.sound = .default
                content.threadIdentifier = mac.id
                AlertActions.tag(content, macID: mac.id, kind: alert.kind, status: MacStore.shared.reading(for: mac)?.status)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            }
        }
    }

    /// Why a widget, Live Activity or Control Center button did nothing; those
    /// surfaces cannot show a reply themselves.
    @MainActor
    static func report(_ failure: String?, for mac: MacStore.Mac) async {
        guard let failure else { return }
        let content = UNMutableNotificationContent()
        content.title = mac.name
        content.body = failure
        content.threadIdentifier = mac.id
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "\(mac.id).command", content: content, trigger: nil))
    }

    /// A control or widget used before any Mac shares with this account.
    @MainActor
    static func reportNoMac() async {
        let content = UNMutableNotificationContent()
        content.body = String(localized: "Open Battistics Remote to connect to your Mac first.")
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "nomac.command", content: content, trigger: nil))
    }

    /// Maintains a rolling local notification while a Keep Awake session is
    /// active, for a Mac that goes quiet while the app is suspended. Each
    /// fresh reading pushes it forward and clears one already delivered; how
    /// far ahead depends on how reliably pushes reach this phone right now.
    @MainActor
    static func syncWatchdog(for mac: MacStore.Mac, reading: MacStore.Reading?) {
        // Shares the `.unreachable` alert identifier, so a foreground refresh
        // and the background timer replace each other instead of stacking.
        let (id, quietID, endingID) = AlertActions.reminderIDs(macID: mac.id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id, quietID, endingID])
        // A fetch settled whether the Mac answers, which the quiet note left open.
        center.removeDeliveredNotifications(withIdentifiers: [quietID])

        guard let reading, reading.reachable, reading.status?.session?.isActive(at: .now) == true else {
            let sessionOver = reading == nil || reading?.status?.sleptAt != nil
                || reading?.status?.session?.isActive(at: .now) != true
            if sessionOver {
                center.removeDeliveredNotifications(withIdentifiers: [id, quietID, endingID])
            }
            return
        }
        // The Mac is answering again: an earlier "stopped answering" alert is now wrong.
        center.removeDeliveredNotifications(withIdentifiers: [id])
        // On Hotspot the lid and unplug warnings no longer apply.
        if reading.status?.network == .hotspot {
            center.removeDeliveredNotifications(withIdentifiers: ["\(mac.id).closedlid", "\(mac.id).unplugged"])
        }
        // Once the lid is shut or the session is over, "you can close the lid" is old news.
        if reading.status?.lidClosed == true || reading.status?.session == nil {
            center.removeDeliveredNotifications(withIdentifiers: ["\(mac.id).bagready"])
        }

        // Added time or a stop makes "ends in 5 minutes" wrong.
        if reading.status?.session?.deadline.map({ $0.timeIntervalSinceNow > endingLead + 30 }) ?? true {
            center.removeDeliveredNotifications(withIdentifiers: [endingID])
        }

        guard isEnabled,
              let status = reading.status,
              let session = status.session else {
            return
        }

        if let deadline = session.deadline, deadline.timeIntervalSinceNow - endingLead > 1 {
            let content = UNMutableNotificationContent()
            content.title = mac.name
            content.body = String(localized: "Keep Awake ends in 5 minutes.")
            content.sound = .default
            content.threadIdentifier = mac.id
            content.categoryIdentifier = endingCategory
            content.userInfo = ["macID": mac.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: deadline.timeIntervalSinceNow - endingLead,
                                                            repeats: false)
            center.add(UNNotificationRequest(identifier: endingID, content: content, trigger: trigger))
        }

        let fireAt = status.readAt.addingTimeInterval(DeliveryCadence.watchdogDelay(for: status))
        if let deadline = session.deadline, deadline <= fireAt { return }
        guard fireAt.timeIntervalSinceNow > 1 else { return }
        let delay = fireAt.timeIntervalSinceNow

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

        // While pushes arrive too unevenly to warn early, a silent note in
        // Notification Center says only that no update came.
        let quietDelay = status.readAt.addingTimeInterval(status.quietDelay).timeIntervalSinceNow
        guard quietDelay < delay - 60 else { return }
        let quiet = UNMutableNotificationContent()
        quiet.title = mac.name
        quiet.body = String(localized: "Last update at \(lastSeen). iOS sometimes holds updates back, so this may be nothing. You get an alert if the Mac stays silent.")
        quiet.interruptionLevel = .passive
        quiet.threadIdentifier = mac.id
        let quietTrigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, quietDelay), repeats: false)
        center.add(UNNotificationRequest(identifier: quietID, content: quiet, trigger: quietTrigger))
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
    var message: String {
        switch self {
        case .sessionEnded(let reason):
            if let reason { String(localized: "Keep Awake ended: \(reason.label).") }
            else { String(localized: "Keep Awake ended.") }
        case .batteryLow(let percent):
            String(localized: "Battery is at \(percent.percentText). Connect power if the Mac must keep running.")
        case .batteryRunsOut(let minutes):
            String(localized: "The battery lasts about \(DurationLabel.long(minutes: minutes)), less than the Keep Awake session.")
        case .unpluggedWithoutHotspot:
            String(localized: "Unplugged on Wi‑Fi while Keep Awake is active. Turn on Personal Hotspot before putting your Mac in a bag so your tasks stay online.")
        case .closedLidWithoutHotspot:
            String(localized: "Lid closed on battery without Hotspot. Connect to Personal Hotspot if you are taking your Mac with you.")
        case .runningHot:
            String(localized: "Running hot during Keep Awake. Open the lid and keep the vents clear, or stop Keep Awake.")
        case .bagReady:
            String(localized: "On Personal Hotspot. You can close the lid and the Mac stays online.")
        case .sleptDuringSession:
            String(localized: "Went to sleep while Keep Awake was on. To keep a closed Mac awake, use Lid Closed.")
        case .chargeReached(let percent):
            String(localized: "Charged to \(percent.percentText). You can unplug it.")
        case .unreachable:
            String(localized: "Stopped answering while Keep Awake was on. Connect to Personal Hotspot or check Wi‑Fi if a task is running.")
        }
    }
}
