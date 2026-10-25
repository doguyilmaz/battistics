import BattisticsRemote
import SwiftUI
import UIKit

@main
struct PhoneApp: App {
    @UIApplicationDelegateAdaptor private var delegate: PhoneAppDelegate
    @State private var store = MacStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("phoneThemePreference") private var themeRaw = "automatic"

    private var colorScheme: ColorScheme? {
        switch themeRaw {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .preferredColorScheme(colorScheme)
                .onAppear { PhoneThemeManager.apply(themeRaw) }
                .onChange(of: themeRaw) { PhoneThemeManager.apply(themeRaw) }
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
        let results = await MacStore.shared.refreshAll()
        if application.applicationState != .active { await Notifications.deliver(results) }
        return .newData
    }
}
