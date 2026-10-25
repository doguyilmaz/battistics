import BattisticsRemote
import Foundation
import Observation
import UIKit

/// What iOS tells an app about this iPhone. Health and cycle count are not
/// available to apps, so the user may copy them from Settings › Battery.
@MainActor
@Observable
final class LocalPhoneMonitor {
    static let shared = LocalPhoneMonitor()

    /// nil where iOS reports no level, as in Simulator.
    private(set) var percent: Int?
    private(set) var isCharging = false
    private(set) var onAdapter = false
    private(set) var lowPowerMode = false
    private(set) var thermal: RemoteStatus.Thermal = .nominal
    private(set) var totalStorage: Int64 = 0
    private(set) var availableStorage: Int64 = 0
    private(set) var chargeHistory: [RemoteStatus.ChargePoint] = []
    /// This iPhone's name as its Personal Hotspot broadcasts it, seen by a Mac on that hotspot.
    private(set) var hotspotName: String?

    var enteredHealth: Int? { didSet { Self.store(enteredHealth, Self.healthKey) } }
    var enteredCycles: Int? { didSet { Self.store(enteredCycles, Self.cyclesKey) } }
    var customName: String { didSet { UserDefaults.standard.set(customName, forKey: Self.nameKey) } }

    let identifier: String
    let modelName: String
    let shortModelName: String
    let memoryGB: Int
    let processorCount: Int

    private static let historyKey = "localPhoneChargeHistory"
    private static let healthKey = "localPhoneCalibratedHealthPercent"
    private static let cyclesKey = "localPhoneCalibratedCycleCount"
    private static let nameKey = "localPhoneCustomDeviceName"
    private static let hotspotKey = "localPhoneDiscoveredName"

    private init() {
        identifier = Self.machineIdentifier()
        (modelName, shortModelName) = Self.marketingName(for: identifier)
        memoryGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        processorCount = ProcessInfo.processInfo.processorCount
        let defaults = UserDefaults.standard
        enteredHealth = defaults.object(forKey: Self.healthKey) as? Int
        enteredCycles = defaults.object(forKey: Self.cyclesKey) as? Int
        customName = defaults.string(forKey: Self.nameKey) ?? ""
        hotspotName = defaults.string(forKey: Self.hotspotKey)
        chargeHistory = Self.loadHistory()

        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                     .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    /// "Dogu’s iPhone" when known; iOS only gives apps the generic "iPhone".
    var displayName: String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return hotspotName ?? String(localized: "This iPhone")
    }

    var pickerName: String { "\(displayName) (\(shortModelName))" }

    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var batteryStatus: RemoteStatus.Battery? {
        percent.map { .init(percent: $0, isCharging: isCharging, onAdapter: onAdapter, lowPowerMode: lowPowerMode) }
    }

    func refresh() {
        let level = UIDevice.current.batteryLevel
        percent = level >= 0 ? Int((level * 100).rounded()) : nil
        let state = UIDevice.current.batteryState
        isCharging = state == .charging
        onAdapter = state == .charging || state == .full
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            totalStorage = Int64(values.volumeTotalCapacity ?? 0)
            availableStorage = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        if let percent { record(Double(percent)) }
    }

    /// A Mac joined to a hotspot reports its network name, which is this iPhone's name.
    func learnHotspotName(from readings: [String: MacStore.Reading]) {
        let names = readings.values.compactMap { reading -> String? in
            guard reading.reachable, let status = reading.status, status.network == .hotspot else { return nil }
            return status.networkName?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let name = names.first, !name.isEmpty, name != hotspotName else { return }
        hotspotName = name
        UserDefaults.standard.set(name, forKey: Self.hotspotKey)
    }

    private func record(_ percent: Double) {
        let now = Date()
        var points = chargeHistory.filter { now.timeIntervalSince($0.at) < 86_400 }
        if let last = points.last, now.timeIntervalSince(last.at) < 600, abs(last.percent - percent) < 1 {
            return
        }
        points.append(.init(at: now, percent: percent))
        chargeHistory = points
        UserDefaults.standard.set(try? RemoteWire.encode(points), forKey: Self.historyKey)
    }

    private static func loadHistory() -> [RemoteStatus.ChargePoint] {
        let points = UserDefaults.standard.data(forKey: historyKey)
            .flatMap { try? RemoteWire.decode([RemoteStatus.ChargePoint].self, from: $0) } ?? []
        return points.filter { Date().timeIntervalSince($0.at) < 86_400 }
    }

    private static func store(_ value: Int?, _ key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private static func machineIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private static func marketingName(for identifier: String) -> (String, String) {
        let short: String? = switch identifier {
        case "iPhone14,7": "14"
        case "iPhone14,8": "14 Plus"
        case "iPhone15,2": "14 Pro"
        case "iPhone15,3": "14 Pro Max"
        case "iPhone15,4": "15"
        case "iPhone15,5": "15 Plus"
        case "iPhone16,1": "15 Pro"
        case "iPhone16,2": "15 Pro Max"
        case "iPhone17,1": "16 Pro"
        case "iPhone17,2": "16 Pro Max"
        case "iPhone17,3": "16"
        case "iPhone17,4": "16 Plus"
        case "iPhone17,5": "16e"
        case "iPhone18,1": "17 Pro"
        case "iPhone18,2": "17 Pro Max"
        case "iPhone18,3": "17"
        case "iPhone18,4": "Air"
        case "iPhone18,5": "17e"
        default: nil
        }
        guard let short else { return ("iPhone", identifier) }
        return ("iPhone \(short)", short)
    }
}
