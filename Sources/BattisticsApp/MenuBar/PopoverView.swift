import BattisticsCore
import Charts
import SwiftUI

/// The at-a-glance view behind the menu bar icon. Also serves as the
/// content of the pinned always-on-top mini window.
struct PopoverView: View {
    var isPinnedWindow = false

    @Environment(AppModel.self) private var model
    @Environment(KeepAwakeModel.self) private var keepAwake
    @Environment(PowerAuthorization.self) private var auth
    @Environment(PowerHelperClient.self) private var helper
    @Environment(PowerSettingsModel.self) private var powerModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue
    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = false
    @State private var windowVisible = false
    @State private var sparklineSelection: Date?

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let snapshot = model.snapshot, snapshot.batteryInstalled {
                HStack(spacing: 28) {
                    GaugeRing(
                        value: Double(snapshot.percent),
                        title: "Charge",
                        color: .charge(
                            percent: Double(snapshot.percent), lowPower: lowPowerIsOn),
                        symbol: snapshot.isCharging ? "bolt.fill" : nil,
                        bottomSymbol: lowPowerIsOn ? "leaf.fill" : nil
                    )
                    GaugeRing(
                        value: snapshot.displayHealthPercent,
                        title: "Health",
                        color: snapshot.hasHealthReading ? .health(percent: snapshot.displayHealthPercent) : .secondary,
                        valueText: snapshot.hasHealthReading ? nil : "—"
                    )
                }
                .frame(maxWidth: .infinity)

                Text(statusText(snapshot))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                chargeDetails(snapshot)
                batteryDetails(snapshot)
                sparklineCard
                if showPowerFlow {
                    PowerFlowSummary()
                }
            } else {
                ContentUnavailableView(
                    "No battery found",
                    systemImage: "minus.plus.batteryblock.exclamationmark",
                    description: Text("Battistics needs a Mac with a built-in battery.")
                )
                .frame(height: 200)
            }
            if let error = keepAwake.errorMessage {
                Text(error).font(.caption)
                    .foregroundStyle(keepAwake.isStoppedReasonInformational ? Color.secondary : Color.red)
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .background(WindowVisibilityReader(isVisible: $windowVisible))
        // Keyed on visibility: the loop dies when the window hides and a
        // fresh one starts when it shows again, even if MenuBarExtra keeps
        // the view alive across popover open/close.
        .task(id: windowVisible) {
            guard windowVisible else { return }
            await model.loadSparkline()
            guard !Task.isCancelled else { return }
            // The popover can be the only thing a menu bar app ever shows, so
            // it cannot rely on the dashboard having primed this.
            helper.refreshStatus()
            await powerModel.refresh()
        }
        .task(id: windowVisible) {
            guard windowVisible else { return }
            await model.refreshSensorsWhileVisible(every: .seconds(2))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(
                nsImage: BatGlyph.image(
                    size: NSSize(width: 26, height: 15),
                    fillFraction: CGFloat(model.snapshot?.percent ?? 0) / 100,
                    charging: model.snapshot?.isCharging ?? false)
            )
            Text("Battistics")
                .font(.headline)
                .fixedSize()
            // Before the Spacer on purpose: everything left of it is
            // left-aligned and everything right of it is pinned right, so the
            // Spacer absorbs the whole width change and nothing moves.
            if keepAwake.isActive {
                keepAwakeChip
            }
            Spacer()
            if !isPinnedWindow {
                Button {
                    openWindow(id: "mini")
                    NSApp.activate()
                } label: {
                    Image(systemName: "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open as a floating window that stays on top")
            }
            if let status = model.snapshot?.healthStatus {
                Text(statusWord(status))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
        }
    }

    private func chargeDetails(_ snapshot: BatterySnapshot) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(
                    title: "Charge",
                    help: [
                        ("Current Charge", "Charge stored now, in milliampere-hours (mAh)."),
                        ("Current Maximum", "Today's full-charge capacity. It declines with age and use."),
                        ("Original Maximum", "The battery's capacity when new."),
                        ("Time on Battery", "Time since the adapter was unplugged."),
                    ])
                StatRow(label: "Current Charge", value: Formatting.mAh(snapshot.rawCurrentCapacity))
                StatRow(label: "Current Maximum", value: Formatting.mAh(snapshot.currentMaxCapacity))
                StatRow(label: "Original Maximum", value: Formatting.mAh(snapshot.designCapacity))
                timeOnBatteryRow
            }
        }
    }

    private func batteryDetails(_ snapshot: BatterySnapshot) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(
                    title: "Battery",
                    help: [
                        ("Cycles", "One full battery's use, possibly across several sessions."),
                        ("Temperature", "Battery temperature. Prolonged heat speeds up aging."),
                        ("Power", "Battery power. Negative means draining; positive means charging."),
                        ("Voltage", "Battery pack voltage."),
                    ])
                StatRow(label: "Cycles", value: "\(snapshot.cycleCount)")
                if let temperature = snapshot.temperatureC {
                    StatRow(
                        label: "Temperature",
                        value: Formatting.temperature(temperature, unit: temperatureUnit))
                }
                if let watts = snapshot.watts {
                    StatRow(
                        label: "Power",
                        value: String(format: "%+.1f W", watts),
                        valueColor: watts < 0 ? .orange : nil)
                }
                if let amperage = snapshot.amperageMA {
                    StatRow(label: "Amperage", value: Formatting.milliamps(amperage))
                }
                if let voltage = snapshot.voltageMV {
                    StatRow(label: "Voltage", value: Formatting.volts(millivolts: voltage))
                }
                if let date = snapshot.manufactureDate {
                    let dateText =
                        snapshot.manufactureDateIsApproximate
                        ? date.formatted(.dateTime.month(.wide).year())
                        : date.formatted(date: .abbreviated, time: .omitted)
                    StatRow(
                        label: "Manufacture Date",
                        value: "\(dateText) · \(Formatting.age(from: date))")
                }
            }
        }
    }

    private var sparklineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Last 24 Hours")
                // Reserve the plot's height before the async history read finishes.
                // Otherwise the first opening grows from a caption into a chart.
                ZStack(alignment: .leading) {
                    if model.sparkline.count > 1 {
                        Chart {
                            ForEach(model.sparkline) { point in
                                AreaMark(
                                    x: .value("Time", point.date),
                                    y: .value("Charge", point.value)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.35), Color.green.opacity(0.03)],
                                        startPoint: .top, endPoint: .bottom))
                                LineMark(
                                    x: .value("Time", point.date),
                                    y: .value("Charge", point.value)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.green)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                            }
                            if let selected = nearestSparklinePoint {
                                RuleMark(x: .value("Time", selected.date))
                                    .foregroundStyle(.secondary.opacity(0.35))
                                PointMark(
                                    x: .value("Time", selected.date),
                                    y: .value("Charge", selected.value)
                                )
                                .foregroundStyle(Color.green)
                                .symbolSize(28)
                                .annotation(
                                    position: .top,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                                ) {
                                    HStack(spacing: 4) {
                                        Text("\(Int(selected.value.rounded()))%")
                                            .font(.caption2.weight(.semibold))
                                        Text(selected.date, format: .dateTime.hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartXSelection(value: $sparklineSelection)
                    } else {
                        Text("Charge history appears here as Battistics runs.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 46)
            }
        }
    }

    /// Matches the banner it replaces: cup, message, and its own close
    /// button. Measured at 117.6pt worst case against 122.2pt of header room,
    /// so it survives the widest health badge and the longest duration.
    private var keepAwakeChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 9))
            Group {
                if windowVisible, let session = keepAwake.session, session.deadline != nil {
                    TimelineView(.periodic(from: session.startedAt, by: 60)) { _ in
                        Text(chipText(at: Date()))
                    }
                } else {
                    Text(chipText(at: Date()))
                }
            }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
            Button {
                keepAwake.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .padding(.leading, 1)
            .help("Turn off Keep Awake")
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }

    private func chipText(at date: Date) -> String {
        guard let seconds = keepAwake.remaining(at: date) else {
            return String(localized: "Awake")
        }
        return String(localized: "Awake · \(Formatting.duration(minutes: Int(seconds / 60)))")
    }

    /// Low Power Mode only. The sleep timers are set-and-forget and belong
    /// in the System pane; this is the one people actually flip.
    ///
    /// Options show whether or not permission is held; picking one asks for
    /// it if needed. The popover does dismiss while the password dialog is up
    /// — MenuBarExtra(.window) closes the moment it stops being key — but by
    /// then the choice is already made and the change still applies, so
    /// there is nothing left to interact with anyway.
    private var powerMenu: some View {
        Menu {
            if let current = powerModel.settings?.lowPowerMode {
                Picker("Low Power Mode", selection: lowPowerBinding(current)) {
                    ForEach(LowPowerModeSetting.allCases, id: \.self) { option in
                        Text(lowPowerLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: lowPowerIsOn ? "leaf.fill" : "leaf")
                .foregroundStyle(lowPowerIsOn ? Color.lowPower : Color.secondary)
        }
        .menuStyle(.button)
        .help("Low Power Mode")
    }

    /// Whether the mode applies to the source in use right now, which is what
    /// makes the icon reflect what the Mac is actually doing.
    private var lowPowerIsOn: Bool {
        powerModel.settings?.lowPowerMode?
            .isActive(onBattery: model.snapshot?.externalConnected == false) ?? false
    }

    private func lowPowerBinding(_ current: LowPowerModeSetting) -> Binding<LowPowerModeSetting> {
        Binding(
            get: { current },
            set: { option in
                Task { @MainActor in
                    await powerModel.apply(.lowPowerMode(option), using: auth, helper: helper)
                }
            })
    }

    private func lowPowerLabel(_ mode: LowPowerModeSetting) -> String {
        switch mode {
        case .never: String(localized: "Never")
        case .always: String(localized: "Always")
        case .onlyOnBattery: String(localized: "Only on battery")
        case .onlyOnPowerAdapter: String(localized: "Only on power adapter")
        }
    }

    private var keepAwakeMenu: some View {
        @Bindable var keepAwake = keepAwake
        return Menu {
            if keepAwake.isActive {
                Button("Turn Off") { keepAwake.stop() }
                Divider()
            }
            Picker("Duration", selection: $keepAwake.duration) {
                ForEach(KeepAwakeDuration.allCases) { duration in
                    Text(duration.label).tag(duration)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Mode", selection: $keepAwake.mode) {
                ForEach(KeepAwakeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        } primaryAction: {
            keepAwake.toggle()
        }
        .menuStyle(.button)
        .help("Keep Awake")
    }

    @ViewBuilder private var footer: some View {
        if !isPinnedWindow {
            HStack {
                Button {
                    model.dashboardPane = .overview
                    openWindow(id: "dashboard")
                    NSApp.activate()
                } label: {
                    // Names the pane it actually opens, and reuses that
                    // pane's own icon. "Dashboard" survives only as an
                    // internal type name.
                    Label("Overview", systemImage: DashboardPane.overview.icon)
                }
                Spacer()
                powerMenu
                keepAwakeMenu.disabled(keepAwake.isChanging)
                Button {
                    model.dashboardPane = .general
                    openWindow(id: "dashboard")
                    NSApp.activate()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Battistics")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder private var timeOnBatteryRow: some View {
        if windowVisible, let unplugged = model.lastUnplugDate {
            TimelineView(.periodic(from: unplugged, by: 60)) { context in
                StatRow(label: "Time on Battery", value: timeOnBattery(at: context.date))
            }
        } else {
            StatRow(label: "Time on Battery", value: timeOnBattery(at: Date()))
        }
    }

    private func timeOnBattery(at date: Date) -> String {
        guard let unplugged = model.lastUnplugDate else { return "N/A" }
        return Formatting.duration(minutes: max(Int(date.timeIntervalSince(unplugged) / 60), 0))
    }

    private var nearestSparklinePoint: SeriesPoint? {
        guard let sparklineSelection, !model.sparkline.isEmpty else { return nil }
        return model.sparkline.min {
            abs($0.date.timeIntervalSince(sparklineSelection))
                < abs($1.date.timeIntervalSince(sparklineSelection))
        }
    }

    private func statusText(_ snapshot: BatterySnapshot) -> String {
        if snapshot.isCharging {
            if let minutes = snapshot.timeRemainingMin {
                return "Charging · \(Formatting.clock(minutes: minutes)) until full"
            }
            return "Charging"
        }
        if snapshot.externalConnected {
            return snapshot.fullyCharged || snapshot.percent >= 100
                ? "Fully charged · plugged in"
                : "Plugged in · charging on hold"
        }
        if let minutes = snapshot.timeRemainingMin {
            return "On battery · \(Formatting.clock(minutes: minutes)) remaining"
        }
        return "On battery"
    }

    private func statusWord(_ status: HealthStatus) -> String {
        switch status {
        case .good: String(localized: "Good")
        case .fair: String(localized: "Fair")
        case .poor: String(localized: "Service")
        }
    }

    private func statusColor(_ status: HealthStatus) -> Color {
        switch status {
        case .good: .green
        case .fair: .orange
        case .poor: .red
        }
    }
}
