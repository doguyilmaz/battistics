import BattisticsCore
import SwiftUI

struct OverviewPane: View {
    @Environment(AppModel.self) private var model
    @Environment(PowerSettingsModel.self) private var powerModel
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

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
                adapterCard(snapshot)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Overview")
        } else {
            ContentUnavailableView(
                "No battery found",
                systemImage: "minus.plus.batteryblock.exclamationmark",
                description: Text("Battistics needs a Mac with a built-in battery.")
            )
        }
    }

    /// Whether Low Power Mode applies to the source in use right now, not
    /// merely whether it is configured.
    private var lowPowerIsOn: Bool {
        powerModel.settings?.lowPowerMode?
            .isActive(onBattery: model.snapshot?.externalConnected == false) ?? false
    }

    private func hero(_ snapshot: BatterySnapshot) -> some View {
        GlassCard(cornerRadius: 16) {
            VStack(spacing: 10) {
                HStack(spacing: 40) {
                    GaugeRing(
                        value: Double(snapshot.percent),
                        title: "Charge",
                        color: .charge(
                            percent: Double(snapshot.percent), lowPower: lowPowerIsOn),
                        symbol: snapshot.isCharging ? "bolt.fill" : nil,
                        bottomSymbol: lowPowerIsOn ? "leaf.fill" : nil,
                        diameter: 112
                    )
                    GaugeRing(
                        value: snapshot.displayHealthPercent,
                        title: "Health",
                        color: .health(percent: snapshot.displayHealthPercent),
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
                StatRow(label: "Measured Maximum", value: Formatting.mAh(snapshot.rawMaxCapacity))
                StatRow(label: "Original Maximum", value: Formatting.mAh(snapshot.designCapacity))
                StatRow(
                    label: "Health",
                    value: Formatting.percentPrecise(snapshot.displayHealthPercent),
                    valueColor: .health(percent: snapshot.displayHealthPercent))
                StatRow(
                    label: "Measured Health",
                    value: Formatting.percentPrecise(snapshot.measuredHealthPercent))
            }
        }
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
                        valueColor: watts < 0 ? .orange : nil)
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

    /// Always four rows, present whether or not anything is plugged in.
    ///
    /// The card used to come and go with the adapter, and each row used to
    /// come and go with its own field — so plugging in grew the pane once for
    /// the card and again for every value IOKit filled in afterwards, which is
    /// why the adapter's name arrived late and moved everything under it.
    /// A dash is a value; an absent row is a layout change.
    private func adapterCard(_ snapshot: BatterySnapshot) -> some View {
        let adapter = snapshot.externalConnected ? snapshot.adapter : nil
        let dash = "—"
        return GlassCard {
            VStack(spacing: 7) {
                SectionHeader(
                    title: "Power Adapter",
                    badge: snapshot.externalConnected ? nil : String(localized: "Not connected"))
                StatRow(label: "Adapter", value: adapter.flatMap(\.name) ?? dash)
                StatRow(
                    label: "Rated Power",
                    value: adapter.flatMap(\.watts).map { "\($0) W" } ?? dash)
                StatRow(
                    label: "Adapter Voltage",
                    value: adapter.flatMap(\.voltageMV)
                        .map { Formatting.volts(millivolts: $0) } ?? dash)
                StatRow(
                    label: "Adapter Current",
                    value: adapter.flatMap(\.amperageMA)
                        .map { Formatting.milliamps($0) } ?? dash)
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
