import BattisticsCore
import SwiftUI

struct OverviewPane: View {
    var isVisible = true
    /// Opens the full battery details.
    var showDetails: () -> Void = {}

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
                    .tourTarget(.overview)
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
            NoBatteryView()
            .tourTarget(.overview)
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
                        color: snapshot.hasHealthReading ? .health(percent: snapshot.displayHealthPercent) : .secondary,
                        valueText: snapshot.hasHealthReading ? nil : "—",
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
                Text(snapshot.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button("Details…", action: showDetails)
                .controlSize(.small)
                .help("Serial number, manufacture date, Apple's rating and a copyable summary")
                .padding(12)
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
                    value: (snapshot.hasHealthReading ? Formatting.percentPrecise(snapshot.displayHealthPercent) : "—"),
                    valueColor: snapshot.hasHealthReading ? .health(percent: snapshot.displayHealthPercent) : .secondary)
                StatRow(
                    label: "Measured Health",
                    value: (snapshot.hasMeasuredHealthReading ? Formatting.percentPrecise(snapshot.measuredHealthPercent) : "—"))
            }
        }
    }

    private func liveCard(_ snapshot: BatterySnapshot) -> some View {
        GlassCard {
            VStack(spacing: 7) {
                SectionHeader(title: "Live")
                LiveBatteryRows(snapshot: snapshot, temperatureUnit: temperatureUnit)
                timeOnBatteryRow
            }
        }
    }

    @ViewBuilder private var timeOnBatteryRow: some View {
        if isVisible, let unplugged = model.lastUnplugDate {
            TimelineView(.periodic(from: unplugged, by: 60)) { context in
                StatRow(label: "Time on Battery", value: model.timeOnBattery(at: context.date))
            }
        } else {
            StatRow(label: "Time on Battery", value: model.timeOnBattery(at: Date()))
        }
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


}
