import BattisticsCore
import SwiftUI

struct OverviewPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both
    }

    var body: some View {
        if let snapshot = model.snapshot, snapshot.batteryInstalled {
            ScrollView {
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
            }
            .navigationTitle("Overview")
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
                HStack(spacing: 48) {
                    GaugeRing(
                        value: Double(snapshot.percent),
                        title: "Charge",
                        color: .charge(percent: Double(snapshot.percent)),
                        symbol: snapshot.isCharging ? "bolt.fill" : nil,
                        diameter: 112
                    )
                    GaugeRing(
                        value: snapshot.healthPercent,
                        title: "Health",
                        color: .health(percent: snapshot.healthPercent),
                        diameter: 112
                    )
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
                    value: Formatting.percentPrecise(snapshot.healthPercent),
                    valueColor: .health(percent: snapshot.healthPercent))
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
