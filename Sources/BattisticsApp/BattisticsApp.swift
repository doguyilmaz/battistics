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
        if UserDefaults.standard.bool(forKey: Prefs.openDashboardAtLaunch),
            let url = URL(string: "battistics://dashboard") {
            NSWorkspace.shared.open(url)
        }
    }
}

@main
struct BattisticsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = UpdaterModel()

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
                .preferredColorScheme(colorScheme)
        } label: {
            MenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Battistics", id: "dashboard") {
            DashboardView()
                .environment(model)
                .environment(updater)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 840, height: 560)
        .handlesExternalEvents(matching: ["dashboard"])

        // Compact always-on-top stats window ("pinned popover").
        Window("Battistics", id: "mini") {
            PopoverView(isPinnedWindow: true)
                .environment(model)
                .environment(updater)
                .preferredColorScheme(colorScheme)
                .background(WindowLevelConfigurator(keepOnTop: true))
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
                .preferredColorScheme(colorScheme)
        }
    }
}
