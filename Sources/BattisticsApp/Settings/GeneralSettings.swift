import BattisticsCore
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdaterModel.self) private var updater
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.showDockIcon) private var showDockIcon = false
    @AppStorage(Prefs.openDashboardAtLaunch) private var openDashboardAtLaunch = false
    @AppStorage(Prefs.keepDashboardOnTop) private var keepDashboardOnTop = false
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var updater = updater
        return Form {
            Section {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled)
                    }
                    // Login Items can be changed in System Settings behind
                    // our back; re-read when the user comes back.
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: NSApplication.didBecomeActiveNotification)
                    ) { _ in
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Open the main window at launch", isOn: $openDashboardAtLaunch)
            }
            Section("Visibility") {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    .disabled(showMenuBarIcon && !showDockIcon)
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .disabled(showDockIcon && !showMenuBarIcon)
                    .onChange(of: showDockIcon) {
                        model.applyActivationPolicy()
                    }
                Text("At least one of the two stays on so Battistics remains reachable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Keep the main window on top", isOn: $keepDashboardOnTop)
            }
            ThemeAndIconSections()
            // Moved from About: it is a setting, and About is for support.
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Download updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                LabeledContent {
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                } label: {
                    Text(lastCheckedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Experiments") {
                HStack {
                    Toggle("Show Power Flow", isOn: $showPowerFlow)
                        .onChange(of: showPowerFlow) { model.refreshSensors() }
                    PowerFlowInfoButton()
                }
                Text("Show power readings in Energy and the popover. On by default; support varies by Mac and macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Units") {
                Picker("Temperature unit", selection: $temperatureUnitRaw) {
                    Text("Celsius and Fahrenheit").tag(TemperatureUnit.both.rawValue)
                    Text("Celsius").tag(TemperatureUnit.celsius.rawValue)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit.rawValue)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Sparkle checks daily, counted from the last check rather than from
    /// launch, so "never" here means it has not run yet, not that it is off.
    private var lastCheckedText: String {
        guard let date = updater.lastCheckDate else {
            return String(localized: "Checked automatically every 24 hours")
        }
        return String(
            localized: "Last checked \(date.formatted(.relative(presentation: .named)))")
    }

    private func updateLoginItem(_ enabled: Bool) {
        // A re-read above changes the toggle too; that is not a request.
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = String(localized: "Could not update the login item: \(error.localizedDescription)")
        }
    }
}
