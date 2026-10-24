import BattisticsRemote
import CoreLocation
import CoreWLAN
import Foundation
import Network
import Observation

/// How this Mac reaches the internet. An iPhone hotspot shows up as an
/// expensive path, which needs no Location permission to detect; the actual
/// Wi‑Fi / Hotspot SSID name is read from CoreWLAN when Location is allowed.
@MainActor
@Observable
final class NetworkMonitor: NSObject, @MainActor CLLocationManagerDelegate {
    private(set) var state: RemoteStatus.Network = .other
    private(set) var ssid: String?
    private(set) var canReadSSID = false
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
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
        locationManager.requestAlwaysAuthorization()
        refreshSSID()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshSSID()
        onChange?()
    }

    private func refreshSSID() {
        let status = locationManager.authorizationStatus
        canReadSSID = (status == .authorizedAlways || status == .authorized)
        if state == .wifi || state == .hotspot {
            let current = CWWiFiClient.shared().interface()?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
            ssid = (current?.isEmpty == false) ? current : nil
        } else {
            ssid = nil
        }
    }

    nonisolated static func state(for path: NWPath) -> RemoteStatus.Network {
        guard path.status == .satisfied else { return .offline }
        if path.isExpensive { return .hotspot }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.wifi) { return .wifi }
        return .other
    }
}
