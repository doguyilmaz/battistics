import BattisticsCore
import SwiftUI

struct DetailsPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both
    }

    var body: some View {
        if let snapshot = model.snapshot, snapshot.batteryInstalled {
            Form {
                Section("Battery") {
                    if let name = snapshot.deviceName {
                        LabeledContent("Model", value: name)
                    }
                    if let serial = snapshot.serialNumber {
                        LabeledContent("Serial Number", value: serial)
                    }
                    if let date = snapshot.manufactureDate {
                        // Serial-derived dates only carry week precision, so
                        // pretending to know the day would be dishonest.
                        let dateText =
                            snapshot.manufactureDateIsApproximate
                            ? date.formatted(.dateTime.month(.wide).year())
                            : date.formatted(date: .abbreviated, time: .omitted)
                        LabeledContent(
                            "Manufacture Date",
                            value: "\(dateText) · \(Formatting.age(from: date))")
                    }
                    LabeledContent("Cycle Count", value: "\(snapshot.cycleCount)")
                    if let designCycles = snapshot.designCycleCount {
                        LabeledContent("Design Cycle Limit", value: "\(designCycles)")
                    }
                }
                Section("Capacity") {
                    LabeledContent("Current Charge", value: Formatting.mAh(snapshot.rawCurrentCapacity))
                    LabeledContent("Current Maximum", value: Formatting.mAh(snapshot.currentMaxCapacity))
                    LabeledContent("Measured Maximum", value: Formatting.mAh(snapshot.rawMaxCapacity))
                    LabeledContent("Design Capacity", value: Formatting.mAh(snapshot.designCapacity))
                    LabeledContent(
                        "Health", value: Formatting.percentPrecise(snapshot.displayHealthPercent))
                    LabeledContent(
                        "Measured Health",
                        value: Formatting.percentPrecise(snapshot.measuredHealthPercent))
                    if let percent = model.appleHealth?.maximumCapacityPercent {
                        LabeledContent("Apple Rated Health", value: "\(percent)%")
                    }
                    if let condition = model.appleHealth?.condition {
                        LabeledContent("Condition", value: condition)
                    }
                }
                Section("Electrical") {
                    if let temperature = snapshot.temperatureC {
                        LabeledContent(
                            "Temperature", value: Formatting.temperature(temperature, unit: temperatureUnit))
                    }
                    if let cell = snapshot.cellTemperatureC, cell != snapshot.temperatureC {
                        LabeledContent(
                            "Cell Sensor", value: Formatting.temperature(cell, unit: temperatureUnit))
                    }
                    if let voltage = snapshot.voltageMV {
                        LabeledContent("Voltage", value: Formatting.volts(millivolts: voltage))
                    }
                    if let amperage = snapshot.amperageMA {
                        LabeledContent("Amperage", value: Formatting.milliamps(amperage))
                    }
                    if let watts = snapshot.watts {
                        LabeledContent("Power", value: String(format: "%+.1f W", watts))
                    }
                }
                if let adapter = snapshot.adapter, snapshot.externalConnected {
                    Section("Power Adapter") {
                        if let name = adapter.name {
                            LabeledContent("Adapter", value: name)
                        }
                        if let watts = adapter.watts {
                            LabeledContent("Rated Power", value: "\(watts) W")
                        }
                        if let voltage = adapter.voltageMV {
                            LabeledContent("Voltage", value: Formatting.volts(millivolts: voltage))
                        }
                        if let current = adapter.amperageMA {
                            LabeledContent("Current", value: Formatting.milliamps(current))
                        }
                    }
                }
                Section {
                    Button("Copy Report") {
                        copyReport(snapshot)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Details")
            .task {
                model.loadAppleHealthIfNeeded()
            }
        } else {
            ContentUnavailableView(
                "No battery found",
                systemImage: "minus.plus.batteryblock.exclamationmark",
                description: Text("Battistics needs a Mac with a built-in battery.")
            )
        }
    }

    private func copyReport(_ snapshot: BatterySnapshot) {
        var lines: [String] = ["Battistics battery report"]
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("")
        if let name = snapshot.deviceName { lines.append("Model: \(name)") }
        if let serial = snapshot.serialNumber { lines.append("Serial: \(serial)") }
        if let date = snapshot.manufactureDate {
            lines.append("Manufactured: \(date.formatted(date: .abbreviated, time: .omitted)) (\(Formatting.age(from: date)))")
        }
        lines.append("Charge: \(snapshot.percent)% (\(Formatting.mAh(snapshot.rawCurrentCapacity)))")
        lines.append("Health: \(Formatting.percentPrecise(snapshot.displayHealthPercent))")
        lines.append("Current maximum: \(Formatting.mAh(snapshot.currentMaxCapacity))")
        lines.append("Measured maximum: \(Formatting.mAh(snapshot.rawMaxCapacity))")
        lines.append("Design capacity: \(Formatting.mAh(snapshot.designCapacity))")
        lines.append("Cycles: \(snapshot.cycleCount)")
        if let temperature = snapshot.temperatureC {
            lines.append("Temperature: \(Formatting.temperature(temperature, unit: .both))")
        }
        if let voltage = snapshot.voltageMV {
            lines.append("Voltage: \(Formatting.volts(millivolts: voltage))")
        }
        if let watts = snapshot.watts {
            lines.append("Power: \(String(format: "%+.1f W", watts))")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
