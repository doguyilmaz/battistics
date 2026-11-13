import BackgroundTasks
import BattisticsRemote
import UIKit
import UserNotifications

/// Notifications for observed events and known session deadlines. Missing
/// background updates never schedule a speculative notification.
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

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func register() {
        Task { await removeLegacySilenceReminders() }
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
                _ = await MacStore.shared.refreshAll(until: .now.advanced(by: MacStore.backgroundRead))
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
        for (mac, alerts) in results {
            for alert in alerts {
                guard isEnabled else { return }
                let id = "\(mac.id).\(alert.kind.rawValue)"
                let content = UNMutableNotificationContent()
                content.title = mac.name
                if alert == .unreachable {
                    // A command or newer refresh may have resolved this while
                    // widget/activity updates were being awaited.
                    guard let status = MacStore.shared.reading(for: mac)?.status,
                          !status.isFresh(), status.sleptAt == nil,
                          status.session?.isActive(at: .now) == true,
                          Date.now >= status.unheardDate else { continue }
                    let lastSeen = status.readAt.formatted(date: .omitted, time: .shortened)
                    content.body = String(localized: "No update from the Mac since \(lastSeen). Check Battistics on the Mac if you need its current status.")
                } else {
                    content.body = alert.message
                }
                content.sound = .default
                content.threadIdentifier = mac.id
                AlertActions.tag(content, macID: mac.id, kind: alert.kind, status: MacStore.shared.reading(for: mac)?.status)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                if !isEnabled {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                    center.removeDeliveredNotifications(withIdentifiers: [id])
                }
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

    /// Cleans obsolete reminders and maintains only the known session end.
    @MainActor
    static func syncReminders(for mac: MacStore.Mac, reading: MacStore.Reading?) async {
        let (id, quietID, endingID) = AlertActions.reminderIDs(macID: mac.id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id, quietID, endingID])
        center.removeDeliveredNotifications(withIdentifiers: [quietID])

        guard let reading, reading.reachable, reading.status?.session?.isActive(at: .now) == true else {
            let sessionOver = reading == nil || reading?.status?.sleptAt != nil
                || reading?.status?.session?.isActive(at: .now) != true
            if sessionOver {
                center.removeDeliveredNotifications(withIdentifiers: [id, quietID, endingID, "\(mac.id).bagready"])
            }
            return
        }
        // A fresh reading resolves an earlier missing-update notice.
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
        if reading.status?.session?.deadline.map({ $0.timeIntervalSinceNow > RemoteReminderPolicy.endingLead + 30 }) ?? true {
            center.removeDeliveredNotifications(withIdentifiers: [endingID])
        }

        guard isEnabled,
              let status = reading.status,
              let fireAt = RemoteReminderPolicy.endingDate(for: status) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = mac.name
        content.body = String(localized: "Keep Awake ends in 5 minutes.")
        content.sound = .default
        content.threadIdentifier = mac.id
        content.categoryIdentifier = endingCategory
        content.userInfo = ["macID": mac.id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireAt.timeIntervalSinceNow, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: endingID, content: content, trigger: trigger))
        // The switch may have changed while the notification was added.
        if !isEnabled { center.removePendingNotificationRequests(withIdentifiers: [endingID]) }
    }

    /// Runs immediately on switch-off, including when iCloud is unavailable.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Upgrade cleanup also covers Macs no longer present in this app's cache.
    static func removeLegacySilenceReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasSuffix(".silent") || $0.hasSuffix(".quiet") })
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.hasSuffix(".silent") || $0.hasSuffix(".quiet") })
        UserDefaults.standard.removeObject(forKey: "backgroundDeliveries")
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
            String(localized: "The Mac’s status is out of date. Check Battistics on the Mac if you need its current status.")
        }
    }
}
