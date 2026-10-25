import AppKit
import BattisticsCore
import SwiftUI

struct NotificationSettings: View {
    @AppStorage(Prefs.alertSoundEnabled) private var soundEnabled = true
    @AppStorage(Prefs.alertLowEnabled) private var lowEnabled = true
    @AppStorage(Prefs.alertLowThreshold) private var lowThreshold = 20
    @AppStorage(Prefs.alertDropEnabled) private var dropEnabled = true
    @AppStorage(Prefs.alertDropStep) private var dropStep = 5
    @AppStorage(Prefs.alertDurationEnabled) private var durationEnabled = false
    @AppStorage(Prefs.alertDurationHours) private var durationHours = 3.0
    @AppStorage(Prefs.alertChargeLimitEnabled) private var chargeLimitEnabled = false
    @AppStorage(Prefs.alertChargeLimitThreshold) private var chargeLimitThreshold = 80
    @AppStorage(Prefs.alertFullEnabled) private var fullEnabled = true
    @AppStorage(Prefs.alertHighTempEnabled) private var highTempEnabled = true
    @AppStorage(Prefs.alertHighTempThreshold) private var highTempThreshold = 40.0
    @AppStorage(Prefs.alertHealthDropEnabled) private var healthDropEnabled = true
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    private var thresholdText: String {
        let unit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both
        return Formatting.temperature(highTempThreshold, unit: unit)
    }

    var body: some View {
        Form {
            Section("On Battery") {
                ThresholdToggle("Low battery", isOn: $lowEnabled, percent: $lowThreshold, range: 5...50)
                    .tourTarget(.notifications)
                Toggle("Remind on every further \(dropStep)% drop", isOn: $dropEnabled)
                    .disabled(!lowEnabled)
                ThresholdToggle(title: "Long time on battery", isOn: $durationEnabled, value: $durationHours,
                                range: 1...12, step: 0.5) { Formatting.duration(minutes: Int($0 * 60)) }
            }
            Section("Charging") {
                ThresholdToggle("Charge limit reached", isOn: $chargeLimitEnabled, percent: $chargeLimitThreshold,
                                range: 50...95)
                Toggle("Fully charged", isOn: $fullEnabled)
            }
            Section("Health") {
                // Stored in Celsius, shown in the unit chosen in General.
                ThresholdToggle(title: "High battery temperature", isOn: $highTempEnabled, value: $highTempThreshold,
                                range: 35...50, step: 1) { _ in thresholdText }
                Toggle("Battery health declines", isOn: $healthDropEnabled)
            }
            Section {
                Toggle("Play sound", isOn: $soundEnabled)
                Button("Open System Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .modifier(TourScrollModifier())
    }
}
