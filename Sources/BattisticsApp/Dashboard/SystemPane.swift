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
    @State private var failure: String?
    @Environment(PowerAuthorization.self) private var auth

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

            Section {
                if let power {
                    if let mode = power.lowPowerMode {
                        if auth.isUnlocked {
                            Picker("Low Power Mode", selection: lowPowerBinding(mode)) {
                                ForEach(LowPowerModeSetting.allCases, id: \.self) { option in
                                    Text(label(for: option)).tag(option)
                                }
                            }
                        } else {
                            LabeledContent("Low Power Mode", value: label(for: mode))
                        }
                    }
                    // Absent on every Mac without a Pro or Max chip, so the
                    // row is skipped rather than shown claiming a default.
                    if let energy = power.energyMode {
                        if auth.isUnlocked {
                            Picker("Energy Mode", selection: energyBinding(energy)) {
                                ForEach(EnergyMode.allCases, id: \.self) { option in
                                    Text(label(for: option)).tag(option)
                                }
                            }
                        } else {
                            LabeledContent("Energy Mode", value: label(for: energy))
                        }
                    }
                    if let source = currentSource(power) {
                        sleepRow("Display Sleep", .display, source.displaySleepMinutes)
                        sleepRow("System Sleep", .system, source.systemSleepMinutes)
                        sleepRow("Disk Sleep", .disk, source.diskSleepMinutes)
                    }
                }
                Button("Open Battery Settings…") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Power")
            } footer: {
                // Now that every row in this section is writable, permission
                // belongs to the section rather than riding one control.
                permissionRow
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System")
        .alert(
            "Could not change the setting", isPresented: failureBinding, presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        // Read once when the pane appears. Power settings change rarely and
        // only from System Settings, so there is nothing here to poll.
        .task { power = await PowerSettingsReader.fetch() }
    }

    // MARK: - Permission

    private var permissionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: auth.isUnlocked ? "lock.open.fill" : "lock.fill")
                .contentTransition(.symbolEffect(.replace))
            Text(permissionText)
            Spacer(minLength: 12)
            if auth.isSupported {
                Button(auth.isUnlocked ? "Revoke" : "Allow…") {
                    auth.isUnlocked ? auth.relock() : requestUnlock()
                }
                .controlSize(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(auth.isUnlocked ? Color.accentColor : Color.secondary)
        .padding(.top, 2)
    }

    private var permissionText: String {
        guard auth.isSupported else {
            return String(localized: "This version of macOS does not allow changing these here.")
        }
        if auth.isUnlocked {
            return String(
                localized: "Battistics can change these. Sleep timers apply to \(sourceName).")
        }
        return String(localized: "Changing these needs your administrator password.")
    }

    private var sourceName: String {
        writeSource == .battery
            ? String(localized: "battery power") : String(localized: "the power adapter")
    }

    private func requestUnlock() {
        do {
            try auth.unlock()
        } catch PowerAuthorization.Failure.cancelled {
            // Dismissing the prompt is not an error.
        } catch {
            failure = String(localized: "Could not get permission to change power settings.")
        }
    }

    // MARK: - Rows

    /// Editable only when the current value is one of the offered stops. A
    /// value set outside the app stays read-only rather than being silently
    /// rounded to something the user did not choose.
    @ViewBuilder
    private func sleepRow(
        _ title: LocalizedStringKey, _ timer: SleepTimer, _ minutes: Int?
    ) -> some View {
        if auth.isUnlocked, let minutes, let interval = SleepInterval(rawValue: minutes) {
            Picker(title, selection: sleepBinding(timer, interval)) {
                ForEach(SleepInterval.allCases, id: \.self) { option in
                    Text(label(for: option)).tag(option)
                }
            }
        } else {
            LabeledContent(title, value: sleepText(minutes))
        }
    }

    // MARK: - Bindings

    private var failureBinding: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    /// Sleep timers are per source, so writing goes to whichever one is in
    /// effect. Using -a would silently flatten the other source's value.
    private var writeSource: PowerSource {
        model.snapshot?.externalConnected == false ? .battery : .ac
    }

    /// Every getter reports what the system actually says, never a local
    /// copy, so a cancelled prompt leaves the control showing reality.
    private func lowPowerBinding(_ current: LowPowerModeSetting) -> Binding<LowPowerModeSetting> {
        Binding(get: { current }, set: { apply(PowerSettingsWriter.arguments(for: $0)) })
    }

    private func energyBinding(_ current: EnergyMode) -> Binding<EnergyMode> {
        Binding(get: { current }, set: { apply(PowerSettingsWriter.arguments(for: $0)) })
    }

    private func sleepBinding(
        _ timer: SleepTimer, _ current: SleepInterval
    ) -> Binding<SleepInterval> {
        Binding(
            get: { current },
            set: {
                apply(
                    PowerSettingsWriter.arguments(
                        for: timer, interval: $0, source: writeSource))
            })
    }

    private func apply(_ arguments: [String]) {
        // Out of the view update before touching Security services.
        Task { @MainActor in
            do {
                try auth.run(arguments)
            } catch {
                failure = String(localized: "Could not change the setting.")
            }
            // Re-read rather than assume the write landed.
            power = await PowerSettingsReader.fetch()
        }
    }

    // MARK: - Labels

    /// Whichever source is actually in effect right now.
    private func currentSource(_ power: PowerSettings) -> PowerSettings.Source? {
        let onBattery = model.snapshot?.externalConnected == false
        return onBattery ? (power.battery ?? power.ac) : (power.ac ?? power.battery)
    }

    private func sleepText(_ minutes: Int?) -> String {
        guard let minutes else { return "\u{2014}" }
        return minutes == 0 ? String(localized: "Never") : String(localized: "\(minutes) min")
    }

    private func label(for interval: SleepInterval) -> String {
        switch interval {
        case .never: String(localized: "Never")
        case .oneHour: String(localized: "1 hour")
        case .twoHours: String(localized: "2 hours")
        case .threeHours: String(localized: "3 hours")
        default: String(localized: "\(interval.rawValue) min")
        }
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
