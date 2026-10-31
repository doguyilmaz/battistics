import BattisticsRemote
import SwiftUI
import UIKit
import UserNotifications

@main
struct PhoneApp: App {
    @UIApplicationDelegateAdaptor private var delegate: PhoneAppDelegate
    @State private var store = MacStore.shared
    @State private var phone = LocalPhoneMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PhoneTheme.key) private var theme = PhoneTheme.automatic

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(phone)
                .onAppear { theme.apply() }
                .onOpenURL { store.open($0) }
                .onChange(of: theme) { theme.apply() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                Notifications.schedule()
                store.publishSelected()
            }
        }
    }
}

/// iCloud wakes the app with a silent push when a Mac's record changes.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifications.register()
        if !DemoData.isEnabled {
            application.registerForRemoteNotifications()
            Task { await MacStore.shared.syncAlertSubscription() }
        }
        return true
    }

    /// Over the app, an alert shows as a banner unless its Mac is on screen,
    /// and stays in Notification Center either way. A refused quick action or
    /// intent always shows.
    ///
    /// The completion handlers are called on the main thread: UIKit aborts
    /// when the one for a tapped notification arrives on another, which an
    /// `async` nonisolated variant does on a cold launch.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        Task { @MainActor in
            if identifier.hasSuffix(".command") { return completionHandler([.banner, .sound]) }
            completionHandler(MacStore.shared.isShowing(alert: identifier) ? [.list] : [.banner, .sound, .list])
        }
    }

    /// Opens the Mac an alert was about, or runs an alert's button: Add 30
    /// Minutes, or Stop Keep Awake, also on the Lock Screen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let request = response.notification.request
        let action = response.actionIdentifier
        let identifier = request.identifier
        let macID = request.content.userInfo["macID"] as? String
        Task { @MainActor in
            await Self.respond(to: action, identifier: identifier, macID: macID)
            completionHandler()
        }
    }

    @MainActor
    private static func respond(to action: String, identifier: String, macID: String?) async {
        // Also on a launch for this action alone, before anything else has created the store.
        let store = MacStore.shared
        if action == Notifications.extendAction, let macID {
            await RemoteIntentBridge.extend?(macID, 30)
        } else if action == AlertActions.stopAction, let macID {
            await RemoteIntentBridge.stop?(macID)
        } else if action == UNNotificationDefaultActionIdentifier {
            store.show(notification: identifier)
        }
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
        -> UIBackgroundFetchResult {
        if application.applicationState != .active { DeliveryCadence.recordBackgroundDelivery() }
        LocalPhoneMonitor.shared.refresh()
        await MacStore.shared.refreshAll(until: .now.advanced(by: MacStore.backgroundRead))
        return .newData
    }
}
