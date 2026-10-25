import BattisticsRemote
import Darwin
import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LocalPhoneMonitor {
    static let shared = LocalPhoneMonitor()

    struct HardwareSpecs: Sendable {
        let marketingName: String
        let shortModelName: String
        let chipName: String
        let boardID: String
        let designCapacityMah: Int
        let nominalVoltageV: Double
        let designCycleLimit: Int

        var designEnergyWh: Double {
            (Double(designCapacityMah) * nominalVoltageV) / 1000.0
        }
    }

    private(set) var percent: Int = 100
    private(set) var isCharging: Bool = false
    private(set) var onAdapter: Bool = false
    private(set) var lowPowerMode: Bool = false
    private(set) var thermal: RemoteStatus.Thermal = .nominal
    private(set) var uptimeSeconds: TimeInterval = 0
    private(set) var totalStorageBytes: Int64 = 0
    private(set) var availableStorageBytes: Int64 = 0
    private(set) var chargeHistory: [RemoteStatus.ChargePoint] = []

    var userHealthPercent: Int {
        didSet {
            UserDefaults.standard.set(userHealthPercent, forKey: Self.healthKey)
        }
    }

    var userCycleCount: Int? {
        didSet {
            if let userCycleCount {
                UserDefaults.standard.set(userCycleCount, forKey: Self.cyclesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.cyclesKey)
            }
        }
    }

    var customDeviceName: String {
        didSet {
            let trimmed = customDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: Self.customNameKey)
        }
    }

    private(set) var discoveredPhoneName: String?

    let machineIdentifier: String
    let specs: HardwareSpecs
    let physicalMemoryGB: Double
    let processorCount: Int
    let activeProcessorCount: Int
    let kernelVersion: String
    let screenResolutionText: String

    private static let historyKey = "localPhoneChargeHistory"
    private static let healthKey = "localPhoneCalibratedHealthPercent"
    private static let cyclesKey = "localPhoneCalibratedCycleCount"
    private static let customNameKey = "localPhoneCustomDeviceName"
    private static let discoveredNameKey = "localPhoneDiscoveredName"

    var modelName: String { specs.marketingName }
    var shortModelName: String { specs.shortModelName }

    var effectiveHealthPercent: Int {
        max(50, min(100, userHealthPercent))
    }

    var effectiveCycleCount: Int? {
        userCycleCount
    }

    var effectiveMaxCapacityMah: Int {
        Int((Double(specs.designCapacityMah) * Double(effectiveHealthPercent) / 100.0).rounded())
    }

    var currentChargeMah: Int {
        Int((Double(effectiveMaxCapacityMah) * Double(percent) / 100.0).rounded())
    }

    var currentEnergyWh: Double {
        (Double(currentChargeMah) * effectiveVoltageV) / 1000.0
    }

    var effectiveMaxEnergyWh: Double {
        (Double(effectiveMaxCapacityMah) * effectiveVoltageV) / 1000.0
    }

    var effectiveVoltageV: Double { specs.nominalVoltageV }

    /// Hourly charge slope (%/h) over recent history when meaningful.
    var chargeRatePerHour: Double? {
        guard chargeHistory.count >= 2 else { return nil }
        let recent = chargeHistory.suffix(6)
        guard let first = recent.first, let last = recent.last else { return nil }
        let dtHours = last.at.timeIntervalSince(first.at) / 3600.0
        guard dtHours >= 0.08 else { return nil }
        let delta = last.percent - first.percent
        guard abs(delta) >= 0.5 else { return nil }
        return delta / dtHours
    }

    var estimatedWatts: Double? {
        guard let rate = chargeRatePerHour else { return nil }
        return (rate / 100.0) * effectiveMaxEnergyWh
    }

    var estimatedMinutesRemaining: Int? {
        if let rate = chargeRatePerHour, abs(rate) >= 1.0 {
            if isCharging && rate > 0 && percent < 100 {
                let remainingPct = Double(max(0, 100 - percent))
                return max(1, Int((remainingPct / rate * 60.0).rounded()))
            } else if !onAdapter && rate < 0 && percent > 0 {
                let remainingPct = Double(max(0, percent))
                return max(1, Int((remainingPct / abs(rate) * 60.0).rounded()))
            }
        }
        // Fallback based on model energy capacity at typical active draw (~1.15W)
        if !onAdapter && percent > 0 {
            let hours = currentEnergyWh / (lowPowerMode ? 0.85 : 1.15)
            return max(5, Int((hours * 60.0).rounded()))
        }
        return nil
    }

    private init() {
        let identifier = Self.readSysctlString("hw.machine") ?? Self.readMachineIdentifier()
        self.machineIdentifier = identifier
        self.specs = Self.hardwareSpecs(for: identifier)
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        self.physicalMemoryGB = (Double(ramBytes) / 1_073_741_824.0 * 10).rounded() / 10
        self.processorCount = ProcessInfo.processInfo.processorCount
        self.activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
        self.kernelVersion = Self.readSysctlString("kern.osrelease") ?? "Darwin"
        let screenBounds = UIScreen.main.nativeBounds
        let scale = UIScreen.main.nativeScale
        self.screenResolutionText = "\(Int(screenBounds.width)) × \(Int(screenBounds.height)) (\(String(format: "%.0fx", scale)))"

        let savedHealth = UserDefaults.standard.integer(forKey: Self.healthKey)
        self.userHealthPercent = (savedHealth >= 50 && savedHealth <= 100) ? savedHealth : 100
        if UserDefaults.standard.object(forKey: Self.cyclesKey) != nil {
            self.userCycleCount = UserDefaults.standard.integer(forKey: Self.cyclesKey)
        } else {
            self.userCycleCount = nil
        }
        self.customDeviceName = UserDefaults.standard.string(forKey: Self.customNameKey) ?? ""
        if let savedDiscovered = UserDefaults.standard.string(forKey: Self.discoveredNameKey) {
            self.discoveredPhoneName = Self.stripTrailingModel(from: savedDiscovered, shortModel: specs.shortModelName, fullModel: specs.marketingName)
        } else {
            self.discoveredPhoneName = nil
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        self.chargeHistory = Self.loadHistory()
        refresh()
    }

    /// Updates discovered phone name from paired Mac readings when available.
    func ingestPairedPhoneName(from readings: [String: MacStore.Reading]) {
        for reading in readings.values {
            if let paired = reading.status?.pairedPhoneName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !paired.isEmpty {
                setDiscoveredName(paired)
                return
            }
            if reading.status?.network == .hotspot,
               let ssid = reading.status?.networkName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ssid.isEmpty {
                setDiscoveredName(ssid)
                return
            }
        }
    }

    private func setDiscoveredName(_ raw: String) {
        let cleaned = Self.stripTrailingModel(from: raw, shortModel: specs.shortModelName, fullModel: specs.marketingName)
        guard !cleaned.isEmpty, cleaned != discoveredPhoneName else { return }
        discoveredPhoneName = cleaned
        UserDefaults.standard.set(cleaned, forKey: Self.discoveredNameKey)
    }

    /// Base user-friendly iPhone name without redundant model suffix, e.g. "Dogu’s iPhone".
    var displayBaseName: String {
        let custom = customDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return Self.stripTrailingModel(from: custom, shortModel: specs.shortModelName, fullModel: specs.marketingName)
        }
        let uiName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uiName.isEmpty && uiName.caseInsensitiveCompare("iPhone") != .orderedSame {
            return Self.stripTrailingModel(from: uiName, shortModel: specs.shortModelName, fullModel: specs.marketingName)
        }
        if let discovered = discoveredPhoneName, !discovered.isEmpty {
            return discovered
        }
        return uiName.isEmpty ? "iPhone" : uiName
    }

    /// Formatted for device pickers: e.g. "Dogu’s iPhone (16e)".
    var pickerDisplayName: String {
        "\(displayBaseName) (\(specs.shortModelName))"
    }

    private static func stripTrailingModel(from name: String, shortModel: String, fullModel: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" (\(fullModel))", " (\(shortModel))", " \(shortModel)"] {
            if result.lowercased().hasSuffix(suffix.lowercased()) {
                result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if result.hasSuffix("’s") || result.hasSuffix("'s") {
            result += " iPhone"
        }
        return result.isEmpty ? name : result
    }

    func refresh() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        if rawLevel >= 0 {
            percent = Int((rawLevel * 100).rounded())
        }
        let state = UIDevice.current.batteryState
        isCharging = (state == .charging)
        onAdapter = (state == .charging || state == .full)
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        uptimeSeconds = ProcessInfo.processInfo.systemUptime

        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) {
            totalStorageBytes = Int64(values.volumeTotalCapacity ?? 0)
            availableStorageBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        recordChargeSample(percent: Double(percent))
    }

    private func recordChargeSample(percent: Double) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-86_400)
        var points = chargeHistory.filter { $0.at >= cutoff }
        if let last = points.last {
            if now.timeIntervalSince(last.at) >= 900 || abs(last.percent - percent) >= 1 {
                points.append(.init(at: now, percent: percent))
            } else {
                points[points.count - 1] = .init(at: now, percent: percent)
            }
        } else {
            points = [
                .init(at: now.addingTimeInterval(-3600), percent: percent),
                .init(at: now, percent: percent)
            ]
        }
        if points.count == 1, let first = points.first {
            points.insert(.init(at: first.at.addingTimeInterval(-3600), percent: first.percent), at: 0)
        }
        chargeHistory = points
        if let encoded = try? RemoteWire.encode(points) {
            UserDefaults.standard.set(encoded, forKey: Self.historyKey)
        }
    }

    private static func loadHistory() -> [RemoteStatus.ChargePoint] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? RemoteWire.decode([RemoteStatus.ChargePoint].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-86_400)
        return decoded.filter { $0.at >= cutoff }
    }

    private static func readSysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func readMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    static func hardwareSpecs(for identifier: String) -> HardwareSpecs {
        switch identifier {
        case "iPhone17,1":
            .init(marketingName: "iPhone 16 Pro", shortModelName: "16 Pro", chipName: "Apple A18 Pro (3 nm)", boardID: "D93AP", designCapacityMah: 3582, nominalVoltageV: 3.88, designCycleLimit: 1000)
        case "iPhone17,2":
            .init(marketingName: "iPhone 16 Pro Max", shortModelName: "16 Pro Max", chipName: "Apple A18 Pro (3 nm)", boardID: "D94AP", designCapacityMah: 4685, nominalVoltageV: 3.87, designCycleLimit: 1000)
        case "iPhone17,3":
            .init(marketingName: "iPhone 16", shortModelName: "16", chipName: "Apple A18 (3 nm)", boardID: "D47AP", designCapacityMah: 3561, nominalVoltageV: 3.89, designCycleLimit: 1000)
        case "iPhone17,4":
            .init(marketingName: "iPhone 16 Plus", shortModelName: "16 Plus", chipName: "Apple A18 (3 nm)", boardID: "D48AP", designCapacityMah: 4674, nominalVoltageV: 3.87, designCycleLimit: 1000)
        case "iPhone17,5":
            .init(marketingName: "iPhone 16e", shortModelName: "16e", chipName: "Apple A18 (3 nm)", boardID: "V59AP", designCapacityMah: 4005, nominalVoltageV: 3.88, designCycleLimit: 1000)
        case "iPhone16,1":
            .init(marketingName: "iPhone 15 Pro", shortModelName: "15 Pro", chipName: "Apple A17 Pro (3 nm)", boardID: "D83AP", designCapacityMah: 3274, nominalVoltageV: 3.88, designCycleLimit: 1000)
        case "iPhone16,2":
            .init(marketingName: "iPhone 15 Pro Max", shortModelName: "15 Pro Max", chipName: "Apple A17 Pro (3 nm)", boardID: "D84AP", designCapacityMah: 4422, nominalVoltageV: 3.87, designCycleLimit: 1000)
        case "iPhone15,4":
            .init(marketingName: "iPhone 15", shortModelName: "15", chipName: "Apple A16 Bionic", boardID: "D37AP", designCapacityMah: 3349, nominalVoltageV: 3.88, designCycleLimit: 1000)
        case "iPhone15,5":
            .init(marketingName: "iPhone 15 Plus", shortModelName: "15 Plus", chipName: "Apple A16 Bionic", boardID: "D38AP", designCapacityMah: 4383, nominalVoltageV: 3.87, designCycleLimit: 1000)
        case "iPhone15,2":
            .init(marketingName: "iPhone 14 Pro", shortModelName: "14 Pro", chipName: "Apple A16 Bionic", boardID: "D73AP", designCapacityMah: 3200, nominalVoltageV: 3.87, designCycleLimit: 500)
        case "iPhone15,3":
            .init(marketingName: "iPhone 14 Pro Max", shortModelName: "14 Pro Max", chipName: "Apple A16 Bionic", boardID: "D74AP", designCapacityMah: 4323, nominalVoltageV: 3.86, designCycleLimit: 500)
        case "iPhone14,7":
            .init(marketingName: "iPhone 14", shortModelName: "14", chipName: "Apple A15 Bionic", boardID: "D27AP", designCapacityMah: 3279, nominalVoltageV: 3.87, designCycleLimit: 500)
        case "iPhone14,8":
            .init(marketingName: "iPhone 14 Plus", shortModelName: "14 Plus", chipName: "Apple A15 Bionic", boardID: "D28AP", designCapacityMah: 4325, nominalVoltageV: 3.86, designCycleLimit: 500)
        default:
            .init(marketingName: "iPhone", shortModelName: identifier, chipName: "Apple Silicon", boardID: identifier, designCapacityMah: 3500, nominalVoltageV: 3.88, designCycleLimit: 1000)
        }
    }
}

struct LocalPhoneDashboard: View {
    @Environment(MacStore.self) private var store
    @State private var showingHotspotHelp = false
    @State private var phone = LocalPhoneMonitor.shared
    @Binding var showingDetails: Bool
    @State private var showCyclesMetric = false
    @State private var showingCalibration = false
    @AppStorage("phoneAmbientEnergyBackdrop") private var showAmbientBackdrop = true

    var body: some View {
        let batterySnapshot = RemoteStatus.Battery(
            percent: phone.percent,
            isCharging: phone.isCharging,
            onAdapter: phone.onAdapter,
            lowPowerMode: phone.lowPowerMode
        )
        let tintColor = PowerPalette.batteryTint(batterySnapshot)

        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if showAmbientBackdrop && (phone.lowPowerMode || phone.isCharging || phone.onAdapter) {
                    PhoneEnergyBackdrop(
                        color: phone.lowPowerMode ? PowerPalette.lowPower : PowerPalette.charging,
                        intensity: phone.lowPowerMode || phone.isCharging ? 0.22 : 0.14
                    )
                    .ignoresSafeArea()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        statusHeader

                        batteryCard(tintColor: tintColor)

                        batteryCapacityCard(tintColor: tintColor)

                        conditionsGrid

                        Spacer(minLength: 0)

                        companionDock
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .frame(minHeight: max(0, proxy.size.height), alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .refreshable {
                    phone.refresh()
                    await store.refreshAll()
                    phone.ingestPairedPhoneName(from: store.readings)
                }
            }
        }
        .sheet(isPresented: $showingCalibration) {
            PhoneBatteryCalibrationSheet()
                .presentationDetents([.medium])
        }
        .task {
            phone.ingestPairedPhoneName(from: store.readings)
            while !Task.isCancelled {
                phone.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phone.lowPowerMode ? PowerPalette.lowPower : .green)
                .frame(width: 7, height: 7)
            Text("Live on \(phone.displayBaseName) · iOS \(UIDevice.current.systemVersion)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                showingDetails = true
            } label: {
                Label(phone.modelName, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    private func batteryCard(tintColor: Color) -> some View {
        let showBorder = phone.lowPowerMode || phone.isCharging || phone.onAdapter
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Gauge(value: Double(phone.percent), in: 0...100) {
                    Image(systemName: phone.lowPowerMode ? "leaf.fill" : (phone.isCharging ? "bolt.fill" : (phone.onAdapter ? "powerplug.fill" : "battery.100")))
                        .foregroundStyle(tintColor)
                        .symbolEffect(.pulse, isActive: phone.isCharging)
                } currentValueLabel: {
                    Text("\(phone.percent)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText(value: Double(phone.percent)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tintColor)
                .scaleEffect(1.22)
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(phone.isCharging ? String(localized: "Charging") : (phone.onAdapter ? String(localized: "Plugged in") : String(localized: "On battery")))
                            .font(.headline)
                        if phone.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PowerPalette.charging)
                        }
                    }
                    Text(batteryHeadlineSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                Button {
                    showingCalibration = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.caption2.weight(.semibold))
                        Text("\(phone.effectiveHealthPercent)%")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                phoneMetricPill(
                    label: phone.estimatedWatts != nil ? String(localized: "Power") : String(localized: "Stored Energy"),
                    value: phonePowerOrEnergyValue,
                    symbol: phone.isCharging ? "bolt.fill" : "bolt.batteryblock.fill",
                    tint: phone.isCharging ? PowerPalette.charging : .secondary
                )

                Button {
                    if phone.effectiveCycleCount != nil {
                        withAnimation(.snappy(duration: 0.22)) {
                            showCyclesMetric.toggle()
                        }
                    } else {
                        showingCalibration = true
                    }
                } label: {
                    phoneMetricPill(
                        label: healthOrCyclesLabel,
                        value: healthOrCyclesValue,
                        symbol: showCyclesMetric && phone.effectiveCycleCount != nil ? "arrow.triangle.2.circlepath" : "heart.fill",
                        tint: phone.effectiveHealthPercent < 80 ? .orange : .secondary
                    )
                }
                .buttonStyle(.plain)

                phoneMetricPill(
                    label: String(localized: "Thermal"),
                    value: phone.thermal.label,
                    symbol: "thermometer.medium",
                    tint: phone.thermal == .nominal ? .secondary : phone.thermal.tint
                )
            }

            if phone.chargeHistory.count > 1 {
                VStack(spacing: 4) {
                    ChargeSparkline(points: phone.chargeHistory, tint: tintColor)
                    HStack {
                        Text("24h ago")
                        Spacer()
                        Text(sparklineRangeLabel)
                        Spacer()
                        Text("Now")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .card(borderColor: showBorder ? tintColor.opacity(0.35) : nil)
    }

    private var batteryHeadlineSubtitle: String {
        if let mins = phone.estimatedMinutesRemaining {
            let duration = DurationLabel.long(minutes: mins)
            if phone.isCharging {
                return String(localized: "\(duration) to full · \(phone.currentChargeMah) mAh")
            }
            return String(localized: "~\(duration) est. · \(phone.currentChargeMah) mAh")
        }
        return "\(phone.currentChargeMah) mAh · \(String(format: "%.1f Wh", phone.currentEnergyWh))"
    }

    private var phonePowerOrEnergyValue: String {
        if let watts = phone.estimatedWatts, abs(watts) >= 0.3 {
            return watts > 0 ? String(format: "+%.1f W", watts) : String(format: "%.1f W", watts)
        }
        return String(format: "%.1f Wh", phone.currentEnergyWh)
    }

    private var healthOrCyclesLabel: String {
        if let cycles = phone.effectiveCycleCount {
            return showCyclesMetric
                ? String(localized: "Cycles")
                : String(localized: "Health · \(cycles)c")
        }
        return String(localized: "Health")
    }

    private var healthOrCyclesValue: String {
        if showCyclesMetric, let cycles = phone.effectiveCycleCount {
            return String(localized: "\(cycles) Cycles")
        }
        return "\(phone.effectiveHealthPercent)%"
    }

    private var sparklineRangeLabel: String {
        let values = phone.chargeHistory.map { Int($0.percent.rounded()) }
        guard let minVal = values.min(), let maxVal = values.max() else {
            return String(localized: "12h ago")
        }
        return String(localized: "Low \(minVal)% · High \(maxVal)%")
    }

    private func batteryCapacityCard(tintColor: Color) -> some View {
        let designMah = max(1, phone.specs.designCapacityMah)
        let currentFraction = min(1.0, max(0.0, Double(phone.currentChargeMah) / Double(designMah)))
        let maxFraction = min(1.0, max(0.0, Double(phone.effectiveMaxCapacityMah) / Double(designMah)))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Battery Capacity", systemImage: "battery.100percent.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("\(phone.specs.designCapacityMah) mAh · \(String(format: "%.1f Wh", phone.specs.designEnergyWh))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 22)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(phone.currentChargeMah) mAh")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text(String(localized: "Current Stored (\(String(format: "%.1f Wh", phone.currentEnergyWh)))"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(phone.effectiveMaxCapacityMah) mAh")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(String(localized: "Max Capacity (\(phone.effectiveHealthPercent)%)"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(tintColor.opacity(0.25))
                            .frame(width: barGeo.size.width * maxFraction)
                        Capsule()
                            .fill(tintColor)
                            .frame(width: barGeo.size.width * currentFraction)
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 60)

            HStack(spacing: 8) {
                capacityMiniStat(
                    title: String(localized: "Design"),
                    value: "\(phone.specs.designCapacityMah) mAh"
                )
                capacityMiniStat(
                    title: String(localized: "Voltage"),
                    value: String(format: "%.2f V", phone.effectiveVoltageV)
                )
                capacityMiniStat(
                    title: String(localized: "Cycle Limit"),
                    value: "\(phone.specs.designCycleLimit)"
                )
            }
            .frame(height: 36)

            HStack(spacing: 8) {
                Button {
                    showingCalibration = true
                } label: {
                    Label("Calibrate Health & Cycles", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingDetails = true
                } label: {
                    Label("Full Specs", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 26)
                }
                .buttonStyle(.bordered)
            }
            .frame(height: 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func capacityMiniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var conditionsGrid: some View {
        let primaryMac = store.macs.first
        let macReading = primaryMac.flatMap { store.reading(for: $0) }
        let freeGB = Double(max(0, phone.availableStorageBytes)) / 1_000_000_000.0

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            Button {
                showingHotspotHelp = true
            } label: {
                phoneTile(
                    title: String(localized: "Personal Hotspot"),
                    value: macReading?.status?.network == .hotspot ? String(localized: "Tethered") : String(localized: "Off"),
                    symbol: "personalhotspot",
                    tint: PowerPalette.hotspot,
                    highlighted: macReading?.status?.network == .hotspot
                )
            }
            .buttonStyle(.plain)
            .hotspotHelp(isPresented: $showingHotspotHelp)

            phoneTile(
                title: String(localized: "Power Mode"),
                value: phone.lowPowerMode ? String(localized: "Low Power") : String(localized: "Standard"),
                symbol: phone.lowPowerMode ? "leaf.fill" : "bolt.circle.fill",
                tint: phone.lowPowerMode ? PowerPalette.lowPower : .secondary
            )

            Button {
                showingDetails = true
            } label: {
                phoneTile(
                    title: String(localized: "Uptime · Storage"),
                    value: "\(formattedUptime(phone.uptimeSeconds)) · \(String(format: "%.0f GB", freeGB))",
                    symbol: "clock.badge.checkmark",
                    tint: .secondary
                )
            }
            .buttonStyle(.plain)

            Button {
                showingDetails = true
            } label: {
                phoneTile(
                    title: phone.specs.chipName,
                    value: "\(String(format: "%.0f GB", phone.physicalMemoryGB)) RAM · \(phone.processorCount)c",
                    symbol: "cpu.fill",
                    tint: .secondary
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var companionDock: some View {
        let primaryMac = store.macs.first
        let reading = primaryMac.flatMap { store.reading(for: $0) }
        let status = reading?.status

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "laptopcomputer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryMac?.name ?? String(localized: "No Mac Connected"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(status.map { status in
                    let pct = status.battery.map { "\($0.percent)%" } ?? ""
                    let sessionText = status.session.map { " · \($0.mode.label)" } ?? ""
                    return "\(pct) · \(status.network.label)\(sessionText)"
                } ?? String(localized: "Enable iPhone access in Battistics on your Mac."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let primaryMac {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        store.selectedID = primaryMac.id
                    }
                } label: {
                    Label("View Mac", systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func phoneMetricPill(label: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint == .secondary ? Color.accentColor : tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func phoneTile(title: String, value: String, symbol: String, tint: Color, highlighted: Bool = false) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint == .secondary ? Color.accentColor : tint)
                .frame(width: 32, height: 32)
                .background((tint == .secondary ? Color.accentColor : tint).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint == .secondary ? Color.primary : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlighted ? PowerPalette.hotspot.opacity(0.10) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(highlighted ? PowerPalette.hotspot.opacity(0.4) : .clear, lineWidth: 1)
        )
    }

    private func formattedUptime(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(60, seconds))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }
}

struct PhoneBatteryCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phone = LocalPhoneMonitor.shared
    @State private var cyclesText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(
                        get: { phone.userHealthPercent },
                        set: { phone.userHealthPercent = $0 }
                    ), in: 50...100) {
                        HStack {
                            Text("Maximum Capacity")
                            Spacer()
                            Text("\(phone.userHealthPercent)%")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    HStack {
                        Text("Cycle Count")
                        Spacer()
                        TextField("e.g. 42", text: $cyclesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline.monospacedDigit())
                            .frame(width: 110)
                            .onChange(of: cyclesText) {
                                let trimmed = cyclesText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let val = Int(trimmed), val >= 0 {
                                    phone.userCycleCount = val
                                } else if trimmed.isEmpty {
                                    phone.userCycleCount = nil
                                }
                            }
                    }
                } header: {
                    Text("iPhone Battery Health & Cycles")
                } footer: {
                    Text("iOS sandboxes raw cycle and health counters from third-party apps. Enter the values shown in iOS Settings › Battery › Battery Health so Battistics can calculate your exact mAh and Wh capacity.")
                }

                Section("Calculated Capacity (\(phone.modelName))") {
                    LabeledContent("Design Capacity", value: "\(phone.specs.designCapacityMah) mAh (\(String(format: "%.1f Wh", phone.specs.designEnergyWh)))")
                    LabeledContent("Estimated Full Capacity", value: "\(phone.effectiveMaxCapacityMah) mAh (\(String(format: "%.1f Wh", phone.effectiveMaxEnergyWh)))")
                    LabeledContent("Current Stored Charge", value: "\(phone.currentChargeMah) mAh (\(String(format: "%.1f Wh", phone.currentEnergyWh)))")
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open iOS Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("Calibrate Battery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let c = phone.userCycleCount {
                    cyclesText = "\(c)"
                }
            }
        }
    }
}

private struct PhoneEnergyBackdrop: View {
    let color: Color
    let intensity: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [color.opacity(intensity), color.opacity(intensity * 0.35), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: geo.size.width * 0.95
                )
            }
        }
        .frame(height: 240)
        .allowsHitTesting(false)
    }
}
