import AppKit
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

    var body: some View {
        Form {
            Section {
                Toggle("Play sound", isOn: $soundEnabled)
            }
            Section("On Battery") {
                Toggle("Low battery", isOn: $lowEnabled)
                if lowEnabled {
                    LabeledContent("Notify at \(lowThreshold)%") {
                        Slider(
                            value: Binding(
                                get: { Double(lowThreshold) },
                                set: { lowThreshold = Int($0) }
                            ), in: 5...50, step: 5)
                    }
                    Toggle("Remind on every further \(dropStep)% drop", isOn: $dropEnabled)
                }
                Toggle("Long time on battery", isOn: $durationEnabled)
                if durationEnabled {
                    LabeledContent("After \(durationHours, format: .number.precision(.fractionLength(0...1))) hours") {
                        Slider(value: $durationHours, in: 1...12, step: 0.5)
                    }
                }
            }
            Section("Charging") {
                Toggle("Charge limit reached", isOn: $chargeLimitEnabled)
                if chargeLimitEnabled {
                    LabeledContent("Notify at \(chargeLimitThreshold)%") {
                        Slider(
                            value: Binding(
                                get: { Double(chargeLimitThreshold) },
                                set: { chargeLimitThreshold = Int($0) }
                            ), in: 50...95, step: 5)
                    }
                }
                Toggle("Fully charged", isOn: $fullEnabled)
            }
            Section("Health") {
                Toggle("High battery temperature", isOn: $highTempEnabled)
                if highTempEnabled {
                    LabeledContent("Above \(Int(highTempThreshold))°C") {
                        Slider(value: $highTempThreshold, in: 35...50, step: 1)
                    }
                }
                Toggle("Battery health declines", isOn: $healthDropEnabled)
            }
            Section {
                Button("Open System Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
