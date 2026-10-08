import Combine
import Sparkle
import SwiftUI
import UserNotifications

/// Identifies the update reminder among the app's notifications.
private let updateNotificationID = "battistics.update"

/// Sparkle 2 wrapper. The updater starts with the app and honors the
/// auto-check / auto-download preferences, which Sparkle persists itself.
@MainActor
@Observable
final class UpdaterModel {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let reminders: UpdateReminders
    @ObservationIgnored private let notificationHandler: UpdateNotificationHandler
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    private(set) var canCheckForUpdates = false
    /// Sparkle's own record. It checks on a 24 hour schedule measured from
    /// this date rather than at launch, so without showing it there is no way
    /// to tell a working updater from a broken one.
    private(set) var lastCheckDate: Date?
    /// Version found by a scheduled check that nobody has looked at yet.
    /// Sparkle holds the alert until `checkForUpdates()` asks for it.
    private(set) var pendingUpdateVersion: String?

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    init() {
        let reminders = UpdateReminders()
        self.reminders = reminders
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: reminders
        )
        notificationHandler = UpdateNotificationHandler()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastCheckDate = value
            }
            .store(in: &cancellables)
        reminders.onFound = { [weak self] version, held in
            self?.remind(about: version, notify: held)
        }
        reminders.onSeen = { [weak self] in self?.clearReminder() }
        notificationHandler.open = { [weak self] in self?.checkForUpdates() }
        // Only update reminders are handled; battery alerts keep their
        // default click behavior, which is to bring the app forward.
        UNUserNotificationCenter.current().delegate = notificationHandler
    }

    /// Also brings back an update Sparkle is holding for a reminder.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// The panel always shows it until it is seen. A notification is only
    /// needed when Sparkle is holding the alert rather than showing it.
    private func remind(about version: String, notify: Bool) {
        pendingUpdateVersion = version
        if notify { Task { await Self.postReminder(for: version) } }
    }

    private func clearReminder() {
        pendingUpdateVersion = nil
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [updateNotificationID])
    }

    /// Never asks for permission: an update is not worth a prompt. Anyone
    /// who allowed battery alerts gets it, everyone else sees the panel.
    private static func postReminder(for version: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Update Available")
        content.body = String(localized: "Battistics \(version) is ready to install. Click to see what's new.")
        try? await center.add(
            UNNotificationRequest(identifier: updateNotificationID, content: content, trigger: nil))
    }
}

/// Sparkle's gentle reminders, which a menu bar app needs.
///
/// Without them Sparkle treats an accessory app found in the background by
/// opening the update alert without activating it, so it lands behind
/// whatever is in front and can sit there unnoticed for weeks. It logs a
/// warning saying exactly that. Now Sparkle shows the alert itself only
/// when it would arrive in focus, which is right after launch; otherwise it
/// holds it, and the panel and a notification point to it.
@MainActor
private final class UpdateReminders: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    /// The version, and whether Sparkle left showing it to us.
    var onFound: ((String, Bool) -> Void)?
    var onSeen: (() -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        // Someone who asked has the alert in front of them already.
        guard !state.userInitiated else { return }
        onFound?(update.displayVersionString, !handleShowingUpdate)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onSeen?()
    }

    func standardUserDriverWillFinishUpdateSession() {
        onSeen?()
    }
}

/// Clicking the update notification opens the alert Sparkle is holding.
private final class UpdateNotificationHandler: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    /// Set once, during `UpdaterModel.init`, before any notification can
    /// be clicked.
    var open: (@MainActor @Sendable () -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == updateNotificationID,
            let open
        else { return }
        await open()
    }
}

struct CheckForUpdatesButton: View {
    var updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
