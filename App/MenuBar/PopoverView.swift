import BattisticsCore
import Charts
import SwiftUI

/// The at-a-glance view behind the menu bar icon.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

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
                        value: snapshot.healthPercent,
                        title: "Health",
                        color: .health(percent: snapshot.healthPercent)
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
        .task {
            await model.loadSparkline()
            while !Task.isCancelled {
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
            Spacer()
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
                StatRow(label: "Current Maximum", value: Formatting.mAh(snapshot.rawMaxCapacity))
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
            }
        }
    }

    private var sparklineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Last 24 Hours")
                if model.sparkline.count > 1 {
                    Chart(model.sparkline) { point in
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
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 42)
                } else {
                    Text("Charge history appears here as Battistics runs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "dashboard")
                NSApp.activate()
            } label: {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Battistics")
        }
        .controlSize(.small)
    }

    private var timeOnBattery: String {
        guard let unplugged = model.lastUnplugDate else { return "N/A" }
        let minutes = Int(Date().timeIntervalSince(unplugged) / 60)
        return Formatting.duration(minutes: max(minutes, 0))
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
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Service"
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
