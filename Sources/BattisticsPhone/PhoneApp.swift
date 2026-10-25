import BattisticsRemote
import SwiftUI
import UIKit

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
            if scenePhase == .background { Notifications.schedule() }
        }
    }
}

/// iCloud wakes the app with a silent push when a Mac's record changes.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Notifications.register()
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
        -> UIBackgroundFetchResult {
        if application.applicationState != .active { DeliveryCadence.recordBackgroundDelivery() }
        await MacStore.shared.refreshAll()
        return .newData
    }
}
