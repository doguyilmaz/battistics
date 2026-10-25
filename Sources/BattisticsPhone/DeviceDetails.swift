import BattisticsRemote
import SwiftUI

struct MacDetailsView: View {
    let mac: MacStore.Mac
    let status: RemoteStatus

    var body: some View {
        let battery = status.battery
        List {
            if let battery {
                Section("Battery") {
                    LabeledContent("Charge", value: battery.percent.percentText)
                    if let health = battery.healthPercent { LabeledContent("Health", value: health.percentText) }
                    if let cycles = battery.cycleCount {
                        LabeledContent("Cycles", value: battery.designCycleCount.map { "\(cycles) / \($0)" } ?? "\(cycles)")
                    }
                    if let date = battery.manufactureDate {
                        LabeledContent("Manufactured", value: date.formatted(.dateTime.month(.wide).year()))
                    }
                }
                Section("Capacity") {
                    if let value = battery.currentCapacityMah { LabeledContent("Current Charge", value: "\(value.formatted()) mAh") }
                    if let value = battery.maxCapacityMah { LabeledContent("Full Charge", value: "\(value.formatted()) mAh") }
                    if let value = battery.designCapacityMah { LabeledContent("Design Capacity", value: "\(value.formatted()) mAh") }
                }
                Section("Electrical") {
                    if let power = battery.powerText { LabeledContent("Power", value: power) }
                    if let mv = battery.voltageMV {
                        LabeledContent("Voltage", value: (Double(mv) / 1000).formatted(.number.precision(.fractionLength(2))) + " V")
                    }
                    if let ma = battery.amperageMA { LabeledContent("Current", value: "\(ma.formatted()) mA") }
                    if let temperature = battery.temperatureText { LabeledContent("Temperature", value: temperature) }
                    LabeledContent("Heat", value: status.thermal.label)
                    if let policy = battery.lowPowerPolicy { LabeledContent("Low Power Mode", value: policy.label) }
                }
                if battery.onAdapter {
                    Section("Power Adapter") {
                        if let name = battery.adapterName, !name.isEmpty { LabeledContent("Adapter", value: name) }
                        if let watts = battery.adapterWatts { LabeledContent("Rated Power", value: "\(watts) W") }
                    }
                }
            }
            Section("Mac") {
                if let model = status.macModel { LabeledContent("Model", value: model) }
                if let os = status.osVersion { LabeledContent("System", value: os) }
                if let name = status.resolvedNetworkName() {
                    LabeledContent(status.network.label, value: name)
                } else {
                    LabeledContent("Network", value: status.network.label)
                }
                LabeledContent("Updated", value: status.readAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(mac.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: summary) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }

    private var summary: String {
        var lines = [mac.name]
        if let model = status.macModel { lines.append(model) }
        if let os = status.osVersion { lines.append(os) }
        if let battery = status.battery {
            lines.append(String(localized: "Charge: \(battery.percent)%"))
            if let health = battery.healthPercent { lines.append(String(localized: "Health: \(health)%")) }
            if let cycles = battery.cycleCount { lines.append(String(localized: "Cycles: \(cycles)")) }
            if let design = battery.designCapacityMah, let full = battery.maxCapacityMah {
                lines.append(String(localized: "Capacity: \(full) / \(design) mAh"))
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct PhoneDetailsView: View {
    @Environment(LocalPhoneMonitor.self) private var phone

    var body: some View {
        List {
            Section("Battery") {
                LabeledContent("Charge", value: phone.percent.map { $0.percentText } ?? "–")
                LabeledContent("State", value: phone.batteryStatus?.headline ?? "–")
                LabeledContent("Low Power Mode", value: phone.lowPowerMode ? String(localized: "On") : String(localized: "Off"))
                LabeledContent("Heat", value: phone.thermal.label)
                if let health = phone.enteredHealth { LabeledContent("Health (entered)", value: health.percentText) }
                if let cycles = phone.enteredCycles { LabeledContent("Cycles (entered)", value: "\(cycles)") }
            }
            Section("iPhone") {
                LabeledContent("Model", value: phone.modelName)
                LabeledContent("Identifier", value: phone.identifier)
                LabeledContent("System", value: "iOS \(UIDevice.current.systemVersion)")
                LabeledContent("Memory", value: "\(phone.memoryGB) GB")
                LabeledContent("Processor Cores", value: "\(phone.processorCount)")
            }
            Section("Storage") {
                LabeledContent("Capacity", value: phone.totalStorage.formatted(.byteCount(style: .file)))
                LabeledContent("Available", value: phone.availableStorage.formatted(.byteCount(style: .file)))
            }
        }
        .navigationTitle(phone.pickerName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
