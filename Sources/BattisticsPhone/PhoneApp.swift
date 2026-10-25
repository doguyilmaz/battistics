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
                .onChange(of: theme) { theme.apply() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                Notifications.schedule()
                QuickActions.update(store.selected.flatMap { store.reading(for: $0) })
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
        application.registerForRemoteNotifications()
        Task { await MacStore.shared.syncAlertSubscription() }
        return true
    }

    /// A refused quick action or intent is the one alert worth showing over the
    /// app; everything else is already on screen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasSuffix(".command") ? [.banner, .sound] : []
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
        await MacStore.shared.refreshAll()
        return .newData
    }
}
