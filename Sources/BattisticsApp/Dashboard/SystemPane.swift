import BattisticsCore
import SwiftUI

/// Live controls over how this Mac behaves, as opposed to the panes that
/// only report on the battery.
struct SystemPane: View {
    @Environment(KeepAwakeModel.self) private var keepAwake
    /// Ticks with the dashboard's existing refresh loop so the countdown
    /// moves without a timer of its own.
    @Environment(AppModel.self) private var model
    @Environment(PowerSettingsModel.self) private var powerModel
    @State private var failure: PaneFailure?

    /// Carries its own title: one hardcoded alert title reused for every
    /// error produced "Could not change the setting / Could not install the
    /// helper", which is two unrelated sentences stapled together.
    private struct PaneFailure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    @Environment(PowerAuthorization.self) private var auth
    @Environment(PowerHelperClient.self) private var helper

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

                if let error = keepAwake.errorMessage {
                    Text(error)
                        .foregroundStyle(keepAwake.isStoppedReasonInformational ? Color.secondary : Color.red)
                }
                if keepAwake.isActive && keepAwake.mode != .displayOn {
                    Button("Sleep Display Now") { keepAwake.sleepDisplayNow() }
                }
                if keepAwake.isActive {
                    LabeledContent("Time remaining", value: remainingText)
                }
            }

            .disabled(keepAwake.isChanging)

            Section {
                Text(
                    "Display modes use a power assertion. Closed-lid mode also uses the power helper to temporarily disable system sleep and restore the previous setting when the session ends."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if let power = powerModel.settings {
                    if let mode = power.lowPowerMode {
                        Picker("Low Power Mode", selection: lowPowerBinding(mode)) {
                            ForEach(LowPowerModeSetting.allCases, id: \.self) { option in
                                Text(label(for: option)).tag(option)
                            }
                        }
                    }
                    // Absent on every Mac without a Pro or Max chip, so the
                    // row is skipped rather than shown claiming a default.
                    if let energy = power.energyMode {
                        Picker("Energy Mode", selection: energyBinding(energy)) {
                            ForEach(EnergyMode.allCases, id: \.self) { option in
                                Text(label(for: option)).tag(option)
                            }
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
            failure?.title ?? "", isPresented: failureBinding, presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        // Read once when the pane appears. Power settings change rarely and
        // only from System Settings, so there is nothing here to poll.
        .task {
            helper.refreshStatus()
            await powerModel.refresh()
        }
    }

    // MARK: - Permission

    private var permissionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: permissionIcon)
                .contentTransition(.symbolEffect(.replace))
            Text(permissionText)
            Spacer(minLength: 12)
            permissionAction
        }
        .font(.caption)
        .foregroundStyle(helper.isInstalled || auth.isUnlocked ? Color.accentColor : Color.secondary)
        .padding(.top, 2)
    }

    @ViewBuilder private var permissionAction: some View {
        if helper.needsApproval {
            Button("Open Login Items…") { helper.openLoginItemsSettings() }
                .controlSize(.small)
        } else if helper.isInstalledButSilent {
            // Registered but not answering has no way out otherwise: the
            // button would offer to remove a helper that is already not
            // working, when re-registering is what fixes it.
            Button("Repair") { repairHelper() }
                .controlSize(.small)
        } else if helper.isInstalled {
            Button("Remove Helper") { removeHelper() }
                .controlSize(.small)
        } else {
            Button("Never Ask Again…") { installHelper() }
                .controlSize(.small)
        }
    }

    private var permissionIcon: String {
        if helper.isInstalledButSilent { return "exclamationmark.triangle.fill" }
        if helper.isInstalled { return "checkmark.seal.fill" }
        return auth.isUnlocked ? "lock.open.fill" : "lock.fill"
    }

    private var permissionText: String {
        if helper.needsApproval {
            return String(
                localized: "macOS needs you to allow Battistics in Login Items first.")
        }
        if helper.isInstalledButSilent {
            return String(
                localized:
                    "The helper is installed but not running, so changes still ask for a password. Repair re-registers it."
            )
        }
        if helper.isInstalled {
            return String(
                localized: "No password needed. Sleep timers apply to \(sourceName).")
        }
        if auth.isUnlocked {
            return String(localized: "Permission granted until Battistics quits.")
        }
        return String(
            localized: "You will be asked for your administrator password on the first change.")
    }

    private func installHelper() {
        do {
            try helper.install()
        } catch {
            // macOS only reveals a recorded denial when a registration is
            // attempted — status reports .notRegistered until then — so this
            // click is the first moment the block can be known. install()
            // has already re-read the status, so the row now offers Login
            // Items and the footer explains why. A modal on top of a control
            // that just became the answer is noise, so nothing is shown.
            guard !helper.needsApproval else { return }
            let underlying = error as NSError
            failure = PaneFailure(
                title: String(localized: "Could not install the helper"),
                message: installFailureMessage(underlying))
        }
    }

    /// One code does not mean one cause. EPERM in particular covers both
    /// "this build is not notarized" and "you have blocked it in Login
    /// Items", so it says both rather than picking one and being wrong half
    /// the time.
    ///
    /// The approval case never reaches here — it is handled by the row
    /// changing rather than by an alert.
    private func installFailureMessage(_ error: NSError) -> String {
        let detail = "\n\n\(error.domain) \(error.code)"
        switch PowerHelperClient.RegistrationError(rawValue: error.code) {
        case .deniedByUser:
            return String(
                localized: "macOS has this blocked. Allow Battistics in Login Items and try again.")
                + detail
        case .invalidSignature, .toolNotValid:
            return String(localized: "The helper's signature was rejected by macOS.") + detail
        case .authorizationFailure:
            return String(localized: "Authorization was refused.") + detail
        case .jobPlistNotFound, .invalidPlist:
            return String(localized: "The helper's configuration is missing or unreadable.")
                + detail
        case .notPermitted:
            return String(
                localized:
                    "macOS refused. Two things cause this: Battistics must be notarized to install a helper, which a local build is not, and the helper must not be blocked in Login Items."
            ) + detail
        default:
            return String(localized: "macOS refused the installation.") + detail
        }
    }

    private func repairHelper() {
        do {
            try helper.reinstall()
        } catch {
            let underlying = error as NSError
            failure = PaneFailure(
                title: String(localized: "Could not repair the helper"),
                message: installFailureMessage(underlying))
        }
    }

    private func removeHelper() {
        do {
            try helper.remove()
        } catch {
            let underlying = error as NSError
            failure = PaneFailure(
                title: String(localized: "Could not remove the helper"),
                message: "\(underlying.domain) \(underlying.code)")
        }
    }

    private var sourceName: String {
        writeSource == .battery
            ? String(localized: "battery power") : String(localized: "the power adapter")
    }

    // MARK: - Rows

    /// Editable only when the current value is one of the offered stops. A
    /// value set outside the app stays read-only rather than being silently
    /// rounded to something the user did not choose.
    @ViewBuilder
    private func sleepRow(
        _ title: LocalizedStringKey, _ timer: SleepTimer, _ minutes: Int?
    ) -> some View {
        if let minutes, let interval = SleepInterval(rawValue: minutes) {
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
        Binding(get: { current }, set: { apply(.lowPowerMode($0)) })
    }

    private func energyBinding(_ current: EnergyMode) -> Binding<EnergyMode> {
        Binding(get: { current }, set: { apply(.energyMode($0)) })
    }

    private func sleepBinding(
        _ timer: SleepTimer, _ current: SleepInterval
    ) -> Binding<SleepInterval> {
        Binding(
            get: { current },
            set: { apply(.sleepTimer(timer, $0, writeSource)) })
    }

    private func apply(_ change: PowerChange) {
        // Out of the view update before touching Security services.
        Task { @MainActor in
            if await powerModel.apply(change, using: auth, helper: helper) == .failed {
                failure = PaneFailure(
                    title: String(localized: "Could not change the setting"),
                    message: String(localized: "macOS refused the change. Nothing was altered."))
            }
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
