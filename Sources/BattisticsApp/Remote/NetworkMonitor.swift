import BattisticsRemote
import CoreLocation
import CoreWLAN
import Foundation
import Network
import Observation
import SystemConfiguration

/// How this Mac reaches the internet. An iPhone hotspot shows up as an
/// expensive path, which needs no Location permission to detect; the actual
/// Wi‑Fi / Hotspot SSID name is read from CoreWLAN when Location is allowed.
@MainActor
@Observable
final class NetworkMonitor: NSObject, @MainActor CLLocationManagerDelegate {
    private(set) var state: RemoteStatus.Network = .other
    private(set) var ssid: String?
    private(set) var preferredHotspotPhoneName: String?
    private(set) var canReadSSID = false
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        preferredHotspotPhoneName = Self.readPreferredHotspotName()
        refreshSSID()
        monitor.pathUpdateHandler = { [weak self] path in
            let state = Self.state(for: path)
            Task { @MainActor in
                guard let self else { return }
                self.state = state
                self.refreshSSID()
                self.onChange?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.doguyilmaz.Battistics.network"))
    }

    func requestSSIDPermission() {
        locationManager.requestWhenInUseAuthorization()
        refreshSSID()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshSSID()
        onChange?()
    }

    private func refreshSSID() {
        let status = locationManager.authorizationStatus
        let current = CWWiFiClient.shared().interface()?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dynamicSSID = Self.readSSIDFromDynamicStore()
        let resolved = (current?.isEmpty == false) ? current : dynamicSSID
        canReadSSID = (status == .authorizedAlways || status == .authorized || resolved != nil)
        if state == .wifi || state == .hotspot {
            ssid = resolved
            if state == .hotspot, let resolved {
                preferredHotspotPhoneName = resolved
            }
        } else {
            ssid = nil
        }
    }

    private static func readSSIDFromDynamicStore() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "com.doguyilmaz.Battistics.ssid" as CFString, nil, nil) else {
            return nil
        }
        let ifName = CWWiFiClient.shared().interface()?.interfaceName ?? "en0"
        let candidates = [
            "State:/Network/Interface/\(ifName)/AirPort",
            "State:/Network/Interface/en0/AirPort",
            "State:/Network/Interface/en1/AirPort"
        ]
        for key in candidates {
            guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let data = dict["CachedScanRecord"] as? Data else {
                continue
            }
            if let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let objects = obj["$objects"] as? [Any] {
                for item in objects {
                    if let d = item as? Data, d.count > 2, d[0] == 0 {
                        let len = Int(d[1])
                        if len > 0 && len <= 32 && d.count >= 2 + len {
                            let ssidData = d.subdata(in: 2..<(2 + len))
                            if let name = String(data: ssidData, encoding: .utf8), !name.isEmpty {
                                return name
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func readPreferredHotspotName() -> String? {
        guard let profiles = CWWiFiClient.shared().interface()?.configuration()?.networkProfiles else {
            return nil
        }
        var candidates: [String] = []
        for case let profile as CWNetworkProfile in profiles {
            if let name = profile.ssid?.trimmingCharacters(in: .whitespacesAndNewlines),
               name.localizedCaseInsensitiveContains("iPhone") {
                candidates.append(name)
            }
        }
        return candidates.first { $0.contains("’") || $0.contains("'") } ?? candidates.first
    }

    nonisolated static func state(for path: NWPath) -> RemoteStatus.Network {
        guard path.status == .satisfied else { return .offline }
        if path.isExpensive { return .hotspot }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.wifi) { return .wifi }
        return .other
    }
}
