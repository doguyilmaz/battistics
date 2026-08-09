import SwiftUI

@main
struct BattisticsApp: App {
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
