import BattisticsRemote
import Foundation
import Network
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
    /// When this app last saw the iPhone come off the charger; nil while charging or before it has seen that.
    private(set) var unpluggedAt: Date?
    /// This iPhone's name as its Personal Hotspot broadcasts it, seen by a Mac on that hotspot.
    private(set) var hotspotName: String?
    enum Connection { case wifi, cellular, wired, offline }
    private(set) var connection: Connection = .offline
    private(set) var lowDataMode = false
    @ObservationIgnored private let path = NWPathMonitor()

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
    private static let hotspotKey = "localPhoneHotspotName"
    private static let unpluggedKey = "localPhoneUnpluggedAt"

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
        // A restart or a charge after the saved unplug, seen while this app was not running, makes it stale.
        let history = chargeHistory
        unpluggedAt = (defaults.object(forKey: Self.unpluggedKey) as? Date).flatMap { unplugged in
            guard unplugged > Self.bootTime else { return nil }
            let after = history.filter { $0.at > unplugged }
            return zip(after, after.dropFirst()).contains { $1.percent > $0.percent } ? nil : unplugged
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                     .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        path.pathUpdateHandler = { [weak self] update in
            let connection: Connection = update.status != .satisfied ? .offline
                : update.usesInterfaceType(.wifi) ? .wifi
                : update.usesInterfaceType(.wiredEthernet) ? .wired : .cellular
            let constrained = update.isConstrained
            Task { @MainActor in
                self?.connection = connection
                self?.lowDataMode = constrained
            }
        }
        path.start(queue: .main)
        refresh()
    }

    /// "Dogu’s iPhone" when known; iOS only gives apps the generic "iPhone".
    var displayName: String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return hotspotName ?? String(localized: "This iPhone")
    }

    /// "Dogu’s iPhone (16e)", without repeating a model the name already ends with.
    var pickerName: String {
        shortModelName.isEmpty || displayName.hasSuffix(shortModelName) ? displayName : "\(displayName) (\(shortModelName))"
    }

    /// How the Mac labels sessions started here; not localized, since the Mac shows it as a name.
    var commandName: String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? hotspotName ?? modelName : custom
    }

    /// Wall-clock time since restart; `systemUptime` leaves out the hours the iPhone slept.
    var uptime: TimeInterval { Date.now.timeIntervalSince(Self.bootTime) }

    private static let bootTime: Date = {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else {
            return Date.now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
        }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }()

    var batteryStatus: RemoteStatus.Battery? {
        percent.map { .init(percent: $0, isCharging: isCharging, onAdapter: onAdapter, lowPowerMode: lowPowerMode) }
    }

    func refresh() {
        let level = UIDevice.current.batteryLevel
        percent = level >= 0 ? Int((level * 100).rounded()) : nil
        let state = UIDevice.current.batteryState
        let wasOnAdapter = onAdapter
        isCharging = state == .charging
        onAdapter = state == .charging || state == .full
        if state != .unknown { trackUnplug(wasOnAdapter: wasOnAdapter) }
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = .init(ProcessInfo.processInfo.thermalState)
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            totalStorage = Int64(values.volumeTotalCapacity ?? 0)
            availableStorage = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        if let percent { record(Double(percent)) }
    }

    /// Percent per hour over the last hour of readings, positive while charging.
    var chargeRate: Double? { ChargeRate.perHour(chargeHistory) }

    /// Only an unplug this app saw counts; one from before it ran stays unknown.
    private func trackUnplug(wasOnAdapter: Bool) {
        let before = unpluggedAt
        if onAdapter {
            unpluggedAt = nil
        } else if wasOnAdapter {
            unpluggedAt = .now
        }
        if unpluggedAt != before { UserDefaults.standard.set(unpluggedAt, forKey: Self.unpluggedKey) }
    }

    /// A Mac joined to a hotspot reports its network name, which is this
    /// iPhone's name while this iPhone is the one sharing.
    func learnHotspotName(from readings: [String: MacStore.Reading]) {
        guard Self.isSharingHotspot() else { return }
        let names = readings.values.compactMap { reading -> String? in
            guard reading.reachable, let status = reading.status, status.network == .hotspot else { return nil }
            return status.networkName?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let name = names.first, !name.isEmpty, name != hotspotName else { return }
        hotspotName = name
        UserDefaults.standard.set(name, forKey: Self.hotspotKey)
    }

    /// Personal Hotspot gives this iPhone 172.20.10.1 on a bridge interface.
    private static func isSharingHotspot() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name).hasPrefix("bridge"),
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            if ip.s_addr == inet_addr("172.20.10.1") { return true }
        }
        return false
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
        case "iPhone11,2": "XS"
        case "iPhone11,4", "iPhone11,6": "XS Max"
        case "iPhone11,8": "XR"
        case "iPhone12,1": "11"
        case "iPhone12,3": "11 Pro"
        case "iPhone12,5": "11 Pro Max"
        case "iPhone12,8", "iPhone14,6": "SE"
        case "iPhone13,1": "12 mini"
        case "iPhone13,2": "12"
        case "iPhone13,3": "12 Pro"
        case "iPhone13,4": "12 Pro Max"
        case "iPhone14,4": "13 mini"
        case "iPhone14,5": "13"
        case "iPhone14,2": "13 Pro"
        case "iPhone14,3": "13 Pro Max"
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
        guard let short else { return (identifier.hasPrefix("iPad") ? "iPad" : "iPhone", "") }
        return ("iPhone \(short)", short)
    }
}
