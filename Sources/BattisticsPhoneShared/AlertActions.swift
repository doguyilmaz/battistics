import BattisticsRemote
import UserNotifications

/// The Stop Keep Awake button on alerts about a running session, for alerts
/// the app posts and alerts the Mac pushes alike.
enum AlertActions {
    static let stopCategory = "keepawake.risk"
    static let stopAction = "stop"

    static var categories: Set<UNNotificationCategory> {
        let stop = UNNotificationAction(identifier: stopAction, title: String(localized: "Stop Keep Awake"))
        return [UNNotificationCategory(identifier: stopCategory, actions: [stop], intentIdentifiers: [])]
    }

    /// Marks an alert with its Mac and, when there is a session to stop by
    /// the Mac's latest known `status`, the button.
    static func tag(_ content: UNMutableNotificationContent, macID: String, kind: RemoteAlert.Kind, status: RemoteStatus?) {
        content.userInfo["macID"] = macID
        if kind.offersStop(sessionRunning: status?.session != nil) { content.categoryIdentifier = stopCategory }
    }
}
