import BattisticsCore
import Charts
import SwiftUI

struct OverviewPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue
    /// Both computed once when the trend loads, not on every body evaluation.
    @State private var healthTrendDomain: ClosedRange<Double> = 80...100
    @State private var healthTrendLine: [SeriesPoint] = []

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both
    }

    var body: some View {
        if let snapshot = model.snapshot, snapshot.batteryInstalled {
            // No ScrollView: the window is fixed-size and sized so the
            // overview always fits.
            VStack(spacing: 16) {
                hero(snapshot)
                HStack(alignment: .top, spacing: 16) {
                    capacityCard(snapshot)
                    liveCard(snapshot)
                }
                if let adapter = snapshot.adapter, snapshot.externalConnected {
                    adapterCard(adapter)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Overview")
            .task {
                await model.loadHealthTrend()
                let readings = model.healthTrend.map(\.displayHealthPercent)
                let smoothed = BatteryHealth.rollingMedian(readings, window: 7)
                healthTrendLine = zip(model.healthTrend, smoothed).map {
                    SeriesPoint(date: $0.date, value: $1)
                }
                healthTrendDomain = max(((readings.min() ?? 80) - 2).rounded(.down), 0)...100
            }
        } else {
            ContentUnavailableView(
                "No battery found",
                systemImage: "minus.plus.batteryblock.exclamationmark",
                description: Text("Battistics needs a Mac with a built-in battery.")
            )
        }
    }

    private func hero(_ snapshot: BatterySnapshot) -> some View {
        GlassCard(cornerRadius: 16) {
            VStack(spacing: 10) {
                HStack(spacing: 40) {
                    GaugeRing(
                        value: Double(snapshot.percent),
                        title: "Charge",
                        color: .charge(percent: Double(snapshot.percent)),
                        symbol: snapshot.isCharging ? "bolt.fill" : nil,
                        diameter: 112
                    )
                    GaugeRing(
                        value: snapshot.displayHealthPercent,
                        title: "Capacity",
                        color: .capacity(percent: snapshot.displayHealthPercent),
                        diameter: 112
                    )
                    if let limit = snapshot.designCycleCount, limit > 0 {
                        GaugeRing(
                            value: Double(snapshot.cycleCount) / Double(limit) * 100,
                            title: "Cycles",
                            color: .cycles(fraction: Double(snapshot.cycleCount) / Double(limit)),
                            valueText: "\(snapshot.cycleCount)",
                            subvalue: "/ \(limit.formatted(.number.grouping(.automatic)))",
                            diameter: 112
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                Text(statusLine(snapshot))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private func capacityCard(_ snapshot: BatterySnapshot) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(title: "Capacity")
                StatRow(label: "Current Charge", value: Formatting.mAh(snapshot.rawCurrentCapacity))
                StatRow(label: "Current Maximum", value: Formatting.mAh(snapshot.currentMaxCapacity))
                StatRow(label: "Original Maximum", value: Formatting.mAh(snapshot.designCapacity))
                StatRow(
                    label: "Capacity",
                    value: Formatting.percentPrecise(snapshot.displayHealthPercent),
                    valueColor: .capacity(percent: snapshot.displayHealthPercent))
                // Absent until there are two daily snapshots, so the card is
                // never padded with an empty box on a fresh install.
                if healthTrendLine.count > 1 {
                    healthTrendChart
                }
            }
        }
    }

    private var healthTrendChart: some View {
        VStack(alignment: .leading, spacing: 3) {
            Chart(healthTrendLine) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Capacity", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.statusInfo.opacity(0.28), Color.statusInfo.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Capacity", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.statusInfo)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYScale(domain: healthTrendDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 34)
            Text("Capacity, last 12 months")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }


    private func liveCard(_ snapshot: BatterySnapshot) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(title: "Live")
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
                        valueColor: watts < 0 ? .statusWarn : nil)
                }
                if let amperage = snapshot.amperageMA {
                    StatRow(label: "Amperage", value: Formatting.milliamps(amperage))
                }
                if let voltage = snapshot.voltageMV {
                    StatRow(label: "Voltage", value: Formatting.volts(millivolts: voltage))
                }
                StatRow(label: "Time on Battery", value: timeOnBattery)
            }
        }
    }

    private var timeOnBattery: String {
        guard let unplugged = model.lastUnplugDate else { return "N/A" }
        return Formatting.duration(minutes: max(Int(Date().timeIntervalSince(unplugged) / 60), 0))
    }

    private func adapterCard(_ adapter: AdapterInfo) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(title: "Power Adapter")
                if let name = adapter.name {
                    StatRow(label: "Adapter", value: name)
                }
                if let watts = adapter.watts {
                    StatRow(label: "Rated Power", value: "\(watts) W")
                }
                if let voltage = adapter.voltageMV {
                    StatRow(label: "Adapter Voltage", value: Formatting.volts(millivolts: voltage))
                }
                if let current = adapter.amperageMA {
                    StatRow(label: "Adapter Current", value: Formatting.milliamps(current))
                }
            }
        }
    }

    private func statusLine(_ snapshot: BatterySnapshot) -> String {
        if snapshot.isCharging {
            if let minutes = snapshot.timeRemainingMin {
                return "Charging · \(Formatting.clock(minutes: minutes)) until full"
            }
            return "Charging"
        }
        if snapshot.externalConnected {
            return snapshot.fullyCharged || snapshot.percent >= 100
                ? "Fully charged · plugged in" : "Plugged in · charging on hold"
        }
        if let minutes = snapshot.timeRemainingMin {
            return "On battery · \(Formatting.clock(minutes: minutes)) remaining"
        }
        return "On battery"
    }
}
