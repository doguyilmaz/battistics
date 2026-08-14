import BattisticsCore
import Charts
import SwiftUI

/// The at-a-glance view behind the menu bar icon. Also serves as the
/// content of the pinned always-on-top mini window.
struct PopoverView: View {
    var isPinnedWindow = false

    @Environment(AppModel.self) private var model
    @Environment(KeepAwakeModel.self) private var keepAwake
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue
    @State private var windowVisible = true
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
                        color: .charge(percent: Double(snapshot.percent)),
                        symbol: snapshot.isCharging ? "bolt.fill" : nil
                    )
                    GaugeRing(
                        value: snapshot.displayHealthPercent,
                        title: "Health",
                        color: .health(percent: snapshot.displayHealthPercent)
                    )
                }
                .frame(maxWidth: .infinity)

                Text(statusText(snapshot))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                chargeDetails(snapshot)
                batteryDetails(snapshot)
                sparklineCard
            } else {
                ContentUnavailableView(
                    "No battery found",
                    systemImage: "minus.plus.batteryblock.exclamationmark",
                    description: Text("Battistics needs a Mac with a built-in battery.")
                )
                .frame(height: 200)
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
            while !Task.isCancelled && windowVisible {
                model.refreshSensors()
                try? await Task.sleep(for: .seconds(2))
            }
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
                        ("Current Charge", "How much energy the battery holds right now, in milliampere-hours."),
                        ("Current Maximum", "The most the battery can hold today. It slowly declines with age and use."),
                        ("Original Maximum", "The design capacity when the battery left the factory."),
                        ("Time on Battery", "Active time since the power adapter was last unplugged."),
                    ])
                StatRow(label: "Current Charge", value: Formatting.mAh(snapshot.rawCurrentCapacity))
                StatRow(label: "Current Maximum", value: Formatting.mAh(snapshot.currentMaxCapacity))
                StatRow(label: "Original Maximum", value: Formatting.mAh(snapshot.designCapacity))
                StatRow(label: "Time on Battery", value: timeOnBattery)
            }
        }
    }

    private func batteryDetails(_ snapshot: BatterySnapshot) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(
                    title: "Battery",
                    help: [
                        ("Cycles", "One cycle is a full discharge worth of use, in any number of sessions."),
                        ("Temperature", "Internal battery temperature. Sustained heat ages a battery faster."),
                        ("Power", "Energy flowing right now. Negative means the battery is draining."),
                        ("Voltage", "The battery pack's current voltage."),
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
                    .frame(height: 46)
                } else {
                    Text("Charge history appears here as Battistics runs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
            Text(chipText)
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

    /// Advanced by the popover's existing 2s refresh loop.
    private var chipText: String {
        guard let seconds = keepAwake.remaining() else {
            return String(localized: "Awake")
        }
        return String(localized: "Awake · \(Formatting.duration(minutes: Int(seconds / 60)))")
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
                keepAwakeMenu
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

    /// Publishes the hosting window's visibility, driven by occlusion
    /// state changes, so sampling is strictly event gated.
    private struct WindowVisibilityReader: NSViewRepresentable {
        @Binding var isVisible: Bool

        func makeNSView(context: Context) -> TrackerView {
            let view = TrackerView()
            view.onChange = { visible in
                Task { @MainActor in
                    isVisible = visible
                }
            }
            return view
        }

        func updateNSView(_ nsView: TrackerView, context: Context) {}

        final class TrackerView: NSView {
            var onChange: ((Bool) -> Void)?
            private var observerToken: ObserverToken?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observerToken = nil
                guard let window else { return }
                onChange?(window.occlusionState.contains(.visible))
                let token = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window, queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        self.onChange?(window.occlusionState.contains(.visible))
                    }
                }
                observerToken = ObserverToken(token)
            }
        }

        /// Removes the notification observer when released, so TrackerView
        /// needs no deinit of its own (an actor-isolated class cannot touch
        /// non-Sendable stored state from its nonisolated deinit).
        private final class ObserverToken: @unchecked Sendable {
            private let token: any NSObjectProtocol

            init(_ token: any NSObjectProtocol) {
                self.token = token
            }

            deinit {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    private var timeOnBattery: String {
        guard let unplugged = model.lastUnplugDate else { return "N/A" }
        let minutes = Int(Date().timeIntervalSince(unplugged) / 60)
        return Formatting.duration(minutes: max(minutes, 0))
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
