import BattisticsRemote
import UIKit

/// The actions on the app icon's menu, following the selected Mac's session.
@MainActor
enum QuickActions {
    private enum Kind: String {
        case start, extend, stop
    }

    static func update(_ reading: MacStore.Reading?) {
        guard let status = reading?.status else {
            UIApplication.shared.shortcutItems = []
            return
        }
        guard let session = status.session, session.isActive(at: .now) else {
            UIApplication.shared.shortcutItems = [
                item(.start, String(localized: "Keep Awake for 1 Hour"), "cup.and.saucer.fill"),
            ]
            return
        }
        var items: [UIApplicationShortcutItem] = []
        if session.deadline != nil { items.append(item(.extend, String(localized: "Add 30 Minutes"), "plus.circle")) }
        items.append(item(.stop, String(localized: "Stop Keep Awake"), "stop.circle"))
        UIApplication.shared.shortcutItems = items
    }

    static func perform(_ shortcut: UIApplicationShortcutItem) {
        // Also on a cold launch, before anything else has created the store.
        _ = MacStore.shared
        Task {
            switch Kind(rawValue: shortcut.type) {
            case .start: await RemoteIntentBridge.start?(.displayMaySleep, 60)
            case .extend: await RemoteIntentBridge.extend?(nil, 30)
            case .stop: await RemoteIntentBridge.stop?(nil)
            case nil: break
            }
        }
    }

    private static func item(_ kind: Kind, _ title: String, _ symbol: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: kind.rawValue, localizedTitle: title, localizedSubtitle: nil,
                                  icon: UIApplicationShortcutIcon(systemImageName: symbol))
    }
}

/// Receives a quick action that launches the app or is chosen while it runs.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let shortcut = options.shortcutItem { Task { @MainActor in QuickActions.perform(shortcut) } }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        await QuickActions.perform(shortcutItem)
        return true
    }
}
