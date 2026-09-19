import BattisticsCore
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.showDockIcon) private var showDockIcon = false
    @AppStorage(Prefs.openDashboardAtLaunch) private var openDashboardAtLaunch = false
    @AppStorage(Prefs.keepDashboardOnTop) private var keepDashboardOnTop = false
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled)
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
            Section("Experiments") {
                HStack {
                    Toggle("Show Power Flow", isOn: $showPowerFlow)
                        .onChange(of: showPowerFlow) { model.refreshSensors() }
                    PowerFlowInfoButton()
                }
                Text("Try a power-flow card in Energy and a compact summary in the popover. Off by default; availability varies by Mac and macOS.")
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

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = "Could not update the login item: \(error.localizedDescription)"
        }
    }
}
