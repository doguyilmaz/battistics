import BattisticsRemote
import Foundation
import Network
import Observation

/// How this Mac reaches the internet. An iPhone hotspot shows up as an
/// expensive path, which needs no Location permission to detect.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var state: RemoteStatus.Network = .other
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state = Self.state(for: path)
            Task { @MainActor in
                self?.state = state
                self?.onChange?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.doguyilmaz.Battistics.network"))
    }

    nonisolated static func state(for path: NWPath) -> RemoteStatus.Network {
        guard path.status == .satisfied else { return .offline }
        if path.isExpensive { return .hotspot }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.wifi) { return .wifi }
        return .other
    }
}
