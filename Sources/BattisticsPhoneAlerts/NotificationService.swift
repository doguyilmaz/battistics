import CloudKit
import UserNotifications

/// Names the Mac on an alert it pushed itself. Push fields are not end-to-end
/// encrypted, so the push carries no Mac name; this iPhone's own copy does.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        // "<Mac ID>.<kind>", sent as a field and as the collapse identifier.
        let collapse = CKQueryNotification(fromRemoteNotificationDictionary: request.content.userInfo)?
            .recordFields?["collapse"] as? String ?? request.identifier
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let dot = collapse.lastIndex(of: ".") else {
            return contentHandler(request.content)
        }
        let macID = String(collapse[..<dot])
        if let name = SharedSnapshot.loadAll().first(where: { $0.macID == macID })?.macName {
            content.subtitle = content.title
            content.title = name
            content.threadIdentifier = macID
        }
        contentHandler(content)
    }
}
