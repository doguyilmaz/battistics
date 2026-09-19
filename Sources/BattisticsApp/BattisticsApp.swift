import SwiftUI

/// A menu bar app must survive its last window closing; SwiftUI's default
/// is to terminate once no regular windows remain, which kills the app the
/// moment Settings closes while the Dock icon is enabled.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opens the dashboard at launch through the app's own URL scheme.
    /// This works in every icon configuration; a view-based approach only
    /// runs when the menu bar label happens to exist.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: Prefs.openDashboardAtLaunch) {
            Self.openDashboard()
        }
    }

    /// Clicking the Dock icon with no open windows sends "reopen"; answer
    /// it with the dashboard, the expected macOS behavior.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            Self.openDashboard()
        }
        return true
    }

    private static func openDashboard() {
        if let url = URL(string: "battistics://dashboard") {
            NSWorkspace.shared.open(url)
        }
    }

    /// battistics://dashboard/<pane> deep links select a dashboard pane.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "battistics" {
            guard let pane = url.pathComponents.dropFirst().first else { continue }
            NotificationCenter.default.post(
                name: .battisticsSelectPane, object: nil, userInfo: ["pane": pane])
        }
    }
}

extension Notification.Name {
    static let battisticsSelectPane = Notification.Name("battisticsSelectPane")
}

@main
struct BattisticsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = UpdaterModel()
    @State private var keepAwake = KeepAwakeModel()
    @State private var powerAuth = PowerAuthorization()
    @State private var powerSettings = PowerSettingsModel()
    @State private var powerHelper = PowerHelperClient()
    @State private var bluetooth = BluetoothGATTReader()

    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.theme) private var themeRaw = ThemePreference.automatic.rawValue

    private var colorScheme: ColorScheme? {
        (ThemePreference(rawValue: themeRaw) ?? .automatic).colorScheme
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            PopoverView()
                .environment(model)
                .environment(updater)
                .environment(keepAwake)
                .environment(powerAuth)
                .environment(powerSettings)
                .environment(powerHelper)
                .environment(bluetooth)
                .preferredColorScheme(colorScheme)
        } label: {
            MenuBarLabelView(snapshot: model.snapshot, keepAwakeActive: keepAwake.isActive)
        }
        .menuBarExtraStyle(.window)

        Window("Battistics", id: "dashboard") {
            DashboardView()
                .environment(model)
                .environment(updater)
                .environment(keepAwake)
                .environment(powerAuth)
                .environment(powerSettings)
                .environment(powerHelper)
                .environment(bluetooth)
                .preferredColorScheme(colorScheme)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["dashboard"])

        // Compact always-on-top stats window ("pinned popover").
        Window("Battistics", id: "mini") {
            PopoverView(isPinnedWindow: true)
                .environment(model)
                .environment(updater)
                .environment(keepAwake)
                .environment(powerAuth)
                .environment(powerSettings)
                .environment(powerHelper)
                .environment(bluetooth)
                .preferredColorScheme(colorScheme)
                .background(WindowLevelConfigurator(keepOnTop: true))
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["mini"])
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            // Settings live inside the dashboard; keep the standard app
            // menu item and Cmd+, pointing there.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.dashboardPane = .general
                    if let url = URL(string: "battistics://dashboard") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
