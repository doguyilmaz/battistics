import Foundation
import Network

@MainActor
final class NearbyLANServer {
    var onConnection: ((NearbyLANLink) -> Void)?
    var onState: ((NearbyLocalNetworkState) -> Void)?
    private(set) var accessState = NearbyLocalNetworkState.inactive
    private(set) var listener: NWListener?
    private var pending: [UUID: NearbyLANLink] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]

    func start(_ credential: NearbyCredential) throws {
        stop()
        let listener = try NWListener(using: NearbyTLS.parameters(credential))
        listener.service = .init(name: credential.discoveryID, type: NearbyTLS.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.listener === listener else { connection.cancel(); return }
                if self.pending.count >= 8 { self.pending.values.first?.close() }
                let link = NearbyLANLink(connection: connection)
                self.pending[link.id] = link
                link.onClose = { [weak self] in
                    self?.pending[link.id] = nil
                    self?.deadlines.removeValue(forKey: link.id)?.cancel()
                }
                link.onReady = { [weak self, weak link] in
                    guard let self, let link, self.listener === listener,
                          self.pending.removeValue(forKey: link.id) === link else { return }
                    self.deadlines.removeValue(forKey: link.id)?.cancel()
                    // Only clients that completed TLS-PSK enter app admission.
                    self.onConnection?(link)
                }
                self.deadlines[link.id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    self?.pending[link.id]?.close()
                }
                link.start()
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.listener === listener else { return }
                switch state {
                case .ready: self.report(.discovering)
                case .waiting(let error): self.report(.failure(error))
                case .failed(let error):
                    self.stop()
                    self.report(.failure(error))
                default: break
                }
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        for link in Array(pending.values) { link.close() }
        for task in deadlines.values { task.cancel() }
        pending = [:]
        deadlines = [:]
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        report(.inactive)
    }

    private func report(_ state: NearbyLocalNetworkState) {
        accessState = state
        onState?(state)
    }
}
