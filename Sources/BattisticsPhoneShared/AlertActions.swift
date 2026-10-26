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

    /// `status` is the Mac's latest known reading. A low battery is also
    /// reported without a session, when there is nothing to stop.
    static func category(for kind: RemoteAlert.Kind, status: RemoteStatus?) -> String? {
        switch kind {
        case .runtime, .hot, .unplugged, .closedlid: stopCategory
        case .battery: status?.session != nil ? stopCategory : nil
        default: nil
        }
    }

    /// Marks an alert with its Mac and button.
    static func tag(_ content: UNMutableNotificationContent, macID: String, kind: RemoteAlert.Kind, status: RemoteStatus?) {
        content.userInfo["macID"] = macID
        if let category = category(for: kind, status: status) { content.categoryIdentifier = category }
    }
}
