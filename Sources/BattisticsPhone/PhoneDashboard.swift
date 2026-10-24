import BattisticsRemote
import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LocalPhoneMonitor {
    static let shared = LocalPhoneMonitor()

    private(set) var percent: Int = 100
    private(set) var isCharging: Bool = false
    private(set) var onAdapter: Bool = false
    private(set) var lowPowerMode: Bool = false
    private(set) var thermal: RemoteStatus.Thermal = .nominal
    private(set) var uptimeSeconds: TimeInterval = 0
    private(set) var totalStorageBytes: Int64 = 0
    private(set) var availableStorageBytes: Int64 = 0
    private(set) var chargeHistory: [RemoteStatus.ChargePoint] = []

    let machineIdentifier: String
    let modelName: String
    let physicalMemoryGB: Int
    let processorCount: Int

    private static let historyKey = "localPhoneChargeHistory"

    private init() {
        let identifier = Self.readMachineIdentifier()
        self.machineIdentifier = identifier
        self.modelName = Self.marketingName(for: identifier)
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        self.physicalMemoryGB = max(1, Int((Double(ramBytes) / 1_073_741_824.0).rounded()))
        self.processorCount = ProcessInfo.processInfo.processorCount
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.chargeHistory = Self.loadHistory()
        refresh()
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

    private static func readMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    static func marketingName(for identifier: String) -> String {
        switch identifier {
        case "iPhone17,1": "iPhone 16 Pro"
        case "iPhone17,2": "iPhone 16 Pro Max"
        case "iPhone17,3": "iPhone 16"
        case "iPhone17,4": "iPhone 16 Plus"
        case "iPhone17,5": "iPhone 16e"
        case "iPhone16,1": "iPhone 15 Pro"
        case "iPhone16,2": "iPhone 15 Pro Max"
        case "iPhone15,4": "iPhone 15"
        case "iPhone15,5": "iPhone 15 Plus"
        case "iPhone15,2": "iPhone 14 Pro"
        case "iPhone15,3": "iPhone 14 Pro Max"
        case "iPhone14,7": "iPhone 14"
        case "iPhone14,8": "iPhone 14 Plus"
        case "iPhone14,2": "iPhone 13 Pro"
        case "iPhone14,3": "iPhone 13 Pro Max"
        case "iPhone14,4": "iPhone 13 mini"
        case "iPhone14,5": "iPhone 13"
        case "iPhone14,6": "iPhone SE (3rd gen)"
        default: UIDevice.current.model
        }
    }
}

struct LocalPhoneDashboard: View {
    @Environment(MacStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var phone = LocalPhoneMonitor.shared

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

                if phone.lowPowerMode || phone.isCharging || phone.onAdapter {
                    PhoneEnergyBackdrop(
                        color: phone.lowPowerMode ? PowerPalette.lowPower : PowerPalette.charging,
                        intensity: phone.lowPowerMode || phone.isCharging ? 0.22 : 0.14
                    )
                    .ignoresSafeArea()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        statusHeader

                        batteryCard(batterySnapshot: batterySnapshot, tintColor: tintColor)

                        systemStorageCard(tintColor: tintColor)

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
                }
            }
        }
        .task {
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
            Text("Live on this iPhone · iOS \(UIDevice.current.systemVersion)")
                .foregroundStyle(.secondary)
            Spacer()
            Label(phone.modelName, systemImage: "iphone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    private func batteryCard(batterySnapshot: RemoteStatus.Battery, tintColor: Color) -> some View {
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
                    Text("\(phone.modelName) · \(UIDevice.current.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: phone.lowPowerMode ? "leaf.fill" : "bolt.circle")
                        .font(.caption2.weight(.semibold))
                    Text(phone.lowPowerMode ? String(localized: "Low Power") : String(localized: "Standard"))
                        .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    phone.lowPowerMode ? PowerPalette.lowPower.opacity(0.20) : Color(.tertiarySystemFill),
                    in: Capsule()
                )
                .foregroundStyle(phone.lowPowerMode ? PowerPalette.lowPower : Color.primary)
            }

            HStack(spacing: 8) {
                phoneMetricPill(
                    label: String(localized: "Power Mode"),
                    value: phone.lowPowerMode ? String(localized: "Low Power") : String(localized: "Normal"),
                    symbol: phone.lowPowerMode ? "leaf.fill" : "bolt.fill",
                    tint: phone.lowPowerMode ? PowerPalette.lowPower : .secondary
                )
                phoneMetricPill(
                    label: String(localized: "Thermal"),
                    value: phone.thermal.label,
                    symbol: "thermometer.medium",
                    tint: phone.thermal == .nominal ? .secondary : phone.thermal.tint
                )
                phoneMetricPill(
                    label: String(localized: "Uptime"),
                    value: formattedUptime(phone.uptimeSeconds),
                    symbol: "clock.fill",
                    tint: .secondary
                )
            }

            if phone.chargeHistory.count > 1 {
                VStack(spacing: 4) {
                    ChargeSparkline(points: phone.chargeHistory, tint: tintColor)
                    HStack {
                        Text("24h ago")
                        Spacer()
                        Text("12h ago")
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

    private func systemStorageCard(tintColor: Color) -> some View {
        let total = max(Int64(1), phone.totalStorageBytes)
        let free = max(Int64(0), phone.availableStorageBytes)
        let used = max(Int64(0), total - free)
        let fraction = min(1.0, max(0.0, Double(used) / Double(total)))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("System & Storage", systemImage: "cpu.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("\(phone.machineIdentifier) · \(phone.processorCount) Cores")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 22)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(formatBytes(used)) / \(formatBytes(total))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Spacer()
                    Text(String(localized: "\(formatBytes(free)) free"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: fraction)
                    .tint(fraction > 0.9 ? .orange : Color.accentColor)
            }
            .frame(height: 76)

            Text(String(localized: "iOS restricts battery cycle & health APIs; open iOS Battery Settings for Apple's health readout."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 18)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                    Text("Open iOS Settings")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var conditionsGrid: some View {
        let primaryMac = store.macs.first
        let macReading = primaryMac.flatMap { store.reading(for: $0) }
        let macPercent = macReading?.status?.battery?.percent

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            Button {
                HotspotOpener.open(using: openURL)
            } label: {
                phoneTile(
                    title: String(localized: "Personal Hotspot"),
                    value: macReading?.status?.network == .hotspot ? String(localized: "Tethered") : String(localized: "Settings"),
                    symbol: "personalhotspot",
                    tint: PowerPalette.hotspot,
                    highlighted: macReading?.status?.network == .hotspot
                )
            }
            .buttonStyle(.plain)

            Button {
                if let primaryMac {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        store.selectedID = primaryMac.id
                    }
                }
            } label: {
                phoneTile(
                    title: primaryMac?.name ?? String(localized: "Your Macs"),
                    value: macPercent.map { "\($0)% · Mac" } ?? String(localized: "\(store.macs.count) Macs"),
                    symbol: "laptopcomputer",
                    tint: .secondary
                )
            }
            .buttonStyle(.plain)

            phoneTile(
                title: String(localized: "Physical Memory"),
                value: "\(phone.physicalMemoryGB) GB RAM",
                symbol: "memorychip.fill",
                tint: .secondary
            )

            phoneTile(
                title: String(localized: "iCloud Companion"),
                value: store.problem == nil ? String(localized: "Connected") : String(localized: "Attention"),
                symbol: "icloud.fill",
                tint: store.problem == nil ? .secondary : .orange
            )
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
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        let totalMinutes = max(1, Int(seconds / 60))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let mins = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        return String(format: "%.0f GB", gb)
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
