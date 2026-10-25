import BattisticsRemote
import SwiftUI
import UIKit

/// Technical Overview & Hardware Details sheet opened from the top-left (i) button.
/// Adapts automatically to the currently selected device (Mac or iPhone).
struct DeviceDetailsSheet: View {
    @Environment(MacStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phone = LocalPhoneMonitor.shared
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLocalPhoneSelected {
                    phoneDetailsContent
                } else if let mac = store.selected, let status = store.reading(for: mac)?.status {
                    macDetailsContent(mac: mac, status: status)
                } else {
                    ContentUnavailableView(
                        "No Device Data",
                        systemImage: "info.circle",
                        description: Text("Wait for your Mac to report or select an iPhone.")
                    )
                }
            }
            .navigationTitle(store.isLocalPhoneSelected ? phone.pickerDisplayName : (store.selected?.name ?? String(localized: "Overview")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Mac Technical Overview & Details

    private func macDetailsContent(mac: MacStore.Mac, status: RemoteStatus) -> some View {
        let battery = status.battery
        let limit = battery?.designCycleCount ?? 1000
        let cycles = battery?.cycleCount ?? 0

        return List {
            if let battery {
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 22) {
                            overviewGauge(
                                value: Double(battery.percent),
                                maxValue: 100,
                                centerText: "\(battery.percent)%",
                                subtitle: String(localized: "Charge"),
                                tint: PowerPalette.batteryTint(battery)
                            )

                            overviewGauge(
                                value: Double(battery.healthPercent ?? 100),
                                maxValue: 100,
                                centerText: battery.healthPercent.map { "\($0)%" } ?? "-",
                                subtitle: String(localized: "Health"),
                                tint: (battery.healthPercent ?? 100) < 80 ? .orange : PowerPalette.charging
                            )

                            overviewGauge(
                                value: Double(min(cycles, limit)),
                                maxValue: Double(max(1, limit)),
                                centerText: "\(cycles)",
                                subtitle: String(localized: "/ \(limit) Cycles"),
                                tint: Double(cycles) / Double(max(1, limit)) > 0.85 ? .orange : .accentColor
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                        if let date = battery.manufactureDate {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                Text("\(date.formatted(.dateTime.month(.abbreviated).year())) · \(Self.ageString(from: date))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Capacity") {
                    if let current = battery.currentCapacityMah {
                        LabeledContent("Current Charge", value: "\(current.formatted()) mAh")
                    }
                    if let maxCap = battery.maxCapacityMah {
                        LabeledContent("Current Maximum", value: "\(maxCap.formatted()) mAh")
                    }
                    if let rawMax = battery.rawMaxCapacityMah {
                        LabeledContent("Measured Maximum", value: "\(rawMax.formatted()) mAh")
                    }
                    if let design = battery.designCapacityMah {
                        LabeledContent("Design Capacity", value: "\(design.formatted()) mAh")
                    }
                    if let health = battery.healthPercent {
                        LabeledContent("Battery Health", value: "\(health)%")
                    }
                }

                Section("Live Electrical") {
                    if let watts = battery.watts {
                        LabeledContent("Power", value: watts > 0 ? String(format: "+%.1f W", watts) : String(format: "%.1f W", watts))
                    }
                    if let mv = battery.voltageMV {
                        LabeledContent("Voltage", value: String(format: "%.2f V", Double(mv) / 1000.0))
                    }
                    if let ma = battery.amperageMA {
                        LabeledContent("Amperage", value: "\(ma > 0 ? "+" : "")\(ma.formatted()) mA")
                    }
                    if let temp = battery.temperatureC {
                        let f = temp * 9 / 5 + 32
                        LabeledContent("Temperature", value: String(format: "%.1f °C / %.1f °F", temp, f))
                    }
                    LabeledContent("Thermal Pressure", value: status.thermal.label)
                    if let policy = battery.lowPowerPolicy {
                        LabeledContent("Low Power Mode Policy", value: policy.label)
                    }
                }

                Section("Power Adapter") {
                    LabeledContent("Status", value: battery.isCharging ? String(localized: "Charging") : (battery.onAdapter ? String(localized: "Connected") : String(localized: "Not connected")))
                    if let name = battery.adapterName, !name.isEmpty {
                        LabeledContent("Adapter", value: name)
                    }
                    if let w = battery.adapterWatts {
                        LabeledContent("Rated Power", value: "\(w) W")
                    }
                    if let mv = battery.adapterVoltageMV {
                        LabeledContent("Adapter Voltage", value: String(format: "%.2f V", Double(mv) / 1000.0))
                    }
                    if let ma = battery.adapterAmperageMA {
                        LabeledContent("Adapter Current", value: "\(ma.formatted()) mA")
                    }
                }
            }

            Section("Hardware & Battery Identity") {
                LabeledContent("Mac Name", value: mac.name)
                if let model = status.macModel {
                    LabeledContent("Model", value: model)
                }
                if let os = status.osVersion {
                    LabeledContent("Operating System", value: os)
                }
                if let date = battery?.manufactureDate {
                    LabeledContent("Battery Age", value: Self.ageString(from: date))
                    LabeledContent("Manufactured", value: date.formatted(.dateTime.month(.wide).year()))
                }
                if let serial = battery?.serialNumber, !serial.isEmpty {
                    LabeledContent("Battery Serial", value: serial)
                }
                if let cycles = battery?.cycleCount {
                    let limit = battery?.designCycleCount ?? 1000
                    LabeledContent("Cycles", value: "\(cycles) / \(limit)")
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = macSummaryReport(mac: mac, status: status)
                    withAnimation { copied = true }
                } label: {
                    Label(copied ? String(localized: "Copied Summary") : String(localized: "Copy Battery Summary"),
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
            }
        }
    }

    // MARK: - iPhone Technical Overview & Hardware Internals

    private var phoneDetailsContent: some View {
        let batterySnapshot = RemoteStatus.Battery(
            percent: phone.percent,
            isCharging: phone.isCharging,
            onAdapter: phone.onAdapter,
            lowPowerMode: phone.lowPowerMode
        )
        let tint = PowerPalette.batteryTint(batterySnapshot)
        let limit = phone.specs.designCycleLimit
        let cycles = phone.effectiveCycleCount ?? 0
        let totalGB = Double(max(1, phone.totalStorageBytes)) / 1_000_000_000.0
        let freeGB = Double(max(0, phone.availableStorageBytes)) / 1_000_000_000.0
        let usedGB = max(0, totalGB - freeGB)
        let bootDate = Date().addingTimeInterval(-phone.uptimeSeconds)

        return List {
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 22) {
                        overviewGauge(
                            value: Double(phone.percent),
                            maxValue: 100,
                            centerText: "\(phone.percent)%",
                            subtitle: String(localized: "Charge"),
                            tint: tint
                        )

                        overviewGauge(
                            value: Double(phone.effectiveHealthPercent),
                            maxValue: 100,
                            centerText: "\(phone.effectiveHealthPercent)%",
                            subtitle: String(localized: "Health"),
                            tint: phone.effectiveHealthPercent < 80 ? .orange : PowerPalette.charging
                        )

                        overviewGauge(
                            value: Double(min(cycles, limit)),
                            maxValue: Double(max(1, limit)),
                            centerText: phone.effectiveCycleCount.map { "\($0)" } ?? "-",
                            subtitle: String(localized: "/ \(limit) Cycles"),
                            tint: .accentColor
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    HStack(spacing: 6) {
                        Image(systemName: "cpu.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("\(phone.modelName) · \(phone.specs.chipName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .padding(.vertical, 6)
            }

            Section("Battery Capacity & Chemistry") {
                LabeledContent("Stored Charge", value: "\(phone.currentChargeMah.formatted()) mAh · \(String(format: "%.1f Wh", phone.currentEnergyWh))")
                LabeledContent("Maximum Capacity", value: "\(phone.effectiveMaxCapacityMah.formatted()) mAh · \(String(format: "%.1f Wh", phone.effectiveMaxEnergyWh))")
                LabeledContent("Design Capacity", value: "\(phone.specs.designCapacityMah.formatted()) mAh · \(String(format: "%.1f Wh", phone.specs.designEnergyWh))")
                LabeledContent("Nominal Voltage", value: String(format: "%.2f V", phone.effectiveVoltageV))
                if let watts = phone.estimatedWatts {
                    LabeledContent("Estimated Power", value: watts > 0 ? String(format: "+%.1f W", watts) : String(format: "%.1f W", watts))
                }
                LabeledContent("Cycle Limit", value: "\(phone.specs.designCycleLimit) cycles (80%)")
                if let temp = phone.ioKitTemperatureC {
                    LabeledContent("Temperature", value: String(format: "%.1f °C", temp))
                }
                LabeledContent("Thermal State", value: phone.thermal.label)
            }

            Section("Hardware Internals") {
                LabeledContent("Marketing Model", value: phone.modelName)
                LabeledContent("Machine Identifier", value: phone.machineIdentifier)
                LabeledContent("Board Configuration", value: phone.specs.boardID)
                LabeledContent("System on Chip", value: phone.specs.chipName)
                LabeledContent("CPU Cores", value: "\(phone.activeProcessorCount) Active / \(phone.processorCount) Total")
                LabeledContent("Physical Memory", value: String(format: "%.1f GB RAM", phone.physicalMemoryGB))
                LabeledContent("Native Display", value: phone.screenResolutionText)
            }

            Section("System & Storage") {
                LabeledContent("Operating System", value: "iOS \(UIDevice.current.systemVersion)")
                LabeledContent("Darwin Kernel", value: phone.kernelVersion)
                LabeledContent("Storage Used", value: String(format: "%.1f / %.0f GB", usedGB, totalGB))
                LabeledContent("Available Space", value: String(format: "%.1f GB", freeGB))
                LabeledContent("System Uptime", value: Self.uptimeString(phone.uptimeSeconds))
                LabeledContent("Last Boot", value: bootDate.formatted(date: .abbreviated, time: .shortened))
            }

            Section {
                Button {
                    UIPasteboard.general.string = phoneSummaryReport()
                    withAnimation { copied = true }
                } label: {
                    Label(copied ? String(localized: "Copied Summary") : String(localized: "Copy Technical Summary"),
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
            }
        }
    }

    private func overviewGauge(value: Double, maxValue: Double, centerText: String, subtitle: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Gauge(value: min(maxValue, max(0, value)), in: 0...maxValue) {
                EmptyView()
            } currentValueLabel: {
                Text(centerText)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .scaleEffect(1.25)
            .frame(width: 68, height: 68)

            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    static func ageString(from date: Date, now: Date = Date()) -> String {
        let days = max(0, now.timeIntervalSince(date) / 86_400.0)
        if days >= 365 {
            let years = (days / 365.25 * 10).rounded() / 10
            return String(localized: "\(String(format: "%.1f", years)) years")
        }
        let months = max(1, Int((days / 30.44).rounded()))
        return String(localized: "\(months) months")
    }

    private static func uptimeString(_ seconds: TimeInterval) -> String {
        let mins = max(1, Int(seconds / 60))
        let d = mins / 1440
        let h = (mins % 1440) / 60
        let m = mins % 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func macSummaryReport(mac: MacStore.Mac, status: RemoteStatus) -> String {
        var lines: [String] = ["Battistics Mac Battery Report"]
        lines.append("Device: \(mac.name)")
        if let model = status.macModel { lines.append("Model: \(model)") }
        if let os = status.osVersion { lines.append("OS: \(os)") }
        if let b = status.battery {
            lines.append("Charge: \(b.percent)% (\(b.currentCapacityMah.map { "\($0) mAh" } ?? "-"))")
            if let h = b.healthPercent { lines.append("Health: \(h)%") }
            if let maxCap = b.maxCapacityMah { lines.append("Current Max: \(maxCap) mAh") }
            if let design = b.designCapacityMah { lines.append("Design Capacity: \(design) mAh") }
            if let c = b.cycleCount { lines.append("Cycles: \(c) / \(b.designCycleCount ?? 1000)") }
            if let date = b.manufactureDate {
                lines.append("Manufactured: \(date.formatted(date: .abbreviated, time: .omitted)) (\(Self.ageString(from: date)))")
            }
            if let w = b.watts { lines.append(String(format: "Power: %.1f W", w)) }
            if let v = b.voltageMV { lines.append(String(format: "Voltage: %.2f V", Double(v) / 1000.0)) }
            if let t = b.temperatureC { lines.append(String(format: "Temperature: %.1f °C", t)) }
        }
        return lines.joined(separator: "\n")
    }

    private func phoneSummaryReport() -> String {
        [
            "Battistics iPhone Technical Report",
            "Device: \(phone.pickerDisplayName)",
            "Identifier: \(phone.machineIdentifier) (\(phone.specs.boardID))",
            "Chip: \(phone.specs.chipName)",
            "OS: iOS \(UIDevice.current.systemVersion) (Darwin \(phone.kernelVersion))",
            "Charge: \(phone.percent)% (\(phone.currentChargeMah) mAh · \(String(format: "%.1f Wh", phone.currentEnergyWh)))",
            "Health: \(phone.effectiveHealthPercent)% (\(phone.effectiveMaxCapacityMah) / \(phone.specs.designCapacityMah) mAh)",
            "Cycles: \(phone.effectiveCycleCount.map(String.init) ?? "-") / \(phone.specs.designCycleLimit)",
            "Memory: \(String(format: "%.1f GB RAM", phone.physicalMemoryGB))",
            "Display: \(phone.screenResolutionText)"
        ].joined(separator: "\n")
    }
}
