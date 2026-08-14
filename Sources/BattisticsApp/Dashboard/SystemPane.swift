import BattisticsCore
import SwiftUI

/// Live controls over how this Mac behaves, as opposed to the panes that
/// only report on the battery.
struct SystemPane: View {
    @Environment(KeepAwakeModel.self) private var keepAwake
    /// Ticks with the dashboard's existing refresh loop so the countdown
    /// moves without a timer of its own.
    @Environment(AppModel.self) private var model
    @State private var power: PowerSettings?

    var body: some View {
        @Bindable var keepAwake = keepAwake
        return Form {
            Section("Keep Awake") {
                Toggle(
                    "Prevent this Mac from sleeping",
                    isOn: Binding(
                        get: { keepAwake.isActive },
                        set: { _ in keepAwake.toggle() }))

                Picker("Mode", selection: $keepAwake.mode) {
                    ForEach(KeepAwakeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if let caption = keepAwake.mode.caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Duration", selection: $keepAwake.duration) {
                    ForEach(KeepAwakeDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }

                if keepAwake.isActive {
                    LabeledContent("Time remaining", value: remainingText)
                }
            }

            Section {
                Text(
                    "Battistics holds a power assertion while this is on, the same mechanism the built-in caffeinate tool uses. It is released when you turn it off, when the timer runs out, or when Battistics quits."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Power") {
                if let power {
                    if let mode = power.lowPowerMode {
                        LabeledContent("Low Power Mode", value: label(for: mode))
                    }
                    // Absent on every Mac without a Pro or Max chip, so the
                    // row is skipped rather than shown claiming a default.
                    if let energy = power.energyMode {
                        LabeledContent("Energy Mode", value: label(for: energy))
                    }
                    if let source = currentSource(power) {
                        LabeledContent("Display Sleep", value: sleepText(source.displaySleepMinutes))
                        LabeledContent("System Sleep", value: sleepText(source.systemSleepMinutes))
                        LabeledContent("Disk Sleep", value: sleepText(source.diskSleepMinutes))
                    }
                }
                Button("Open Battery Settings…") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section {
                Text(
                    "These are macOS's own settings, shown for the power source in use. Battistics reads them and does not change them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System")
        // Read once when the pane appears. Power settings change rarely and
        // only from System Settings, so there is nothing here to poll.
        .task { power = await PowerSettingsReader.fetch() }
    }

    /// Whichever source is actually in effect right now.
    private func currentSource(_ power: PowerSettings) -> PowerSettings.Source? {
        let onBattery = model.snapshot?.externalConnected == false
        return onBattery ? (power.battery ?? power.ac) : (power.ac ?? power.battery)
    }

    private func sleepText(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        return minutes == 0 ? String(localized: "Never") : String(localized: "\(minutes) min")
    }

    private func label(for mode: LowPowerModeSetting) -> String {
        switch mode {
        case .never: String(localized: "Never")
        case .always: String(localized: "Always")
        case .onlyOnBattery: String(localized: "Only on battery")
        case .onlyOnPowerAdapter: String(localized: "Only on power adapter")
        }
    }

    private func label(for mode: EnergyMode) -> String {
        switch mode {
        case .automatic: String(localized: "Automatic")
        case .low: String(localized: "Low Power")
        case .high: String(localized: "High Power")
        }
    }

    private var remainingText: String {
        // Reading the snapshot subscribes this view to the dashboard's
        // refresh loop, which is what re-evaluates the countdown.
        _ = model.snapshot
        guard let seconds = keepAwake.remaining() else {
            return String(localized: "Until turned off")
        }
        return Formatting.duration(minutes: Int(seconds / 60))
    }
}
