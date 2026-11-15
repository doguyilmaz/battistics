import Foundation
import Network

@MainActor
final class NearbyLANServer {
    var onConnection: ((NearbyLANLink) -> Void)?
    private(set) var listener: NWListener?

    func start(_ credential: NearbyCredential) throws {
        stop()
        let listener = try NWListener(using: NearbyTLS.parameters(credential))
        listener.service = .init(name: credential.discoveryID, type: NearbyTLS.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.listener === listener else { connection.cancel(); return }
                self.onConnection?(NearbyLANLink(connection: connection))
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    guard let self, self.listener === listener else { return }
                    self.stop()
                }
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }
}
