import Foundation
import Network

@MainActor
final class NearbyLANLink: NearbyLink {
    let id = UUID()
    let kind = RemoteRoute.Kind.lan
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private var closed = false
    private var queuedBytes = 0

    init(connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                switch state {
                case .ready: self.onReady?()
                case .failed, .cancelled: self.close()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ data: Data) throws {
        guard !closed, queuedBytes + data.count <= 512 * 1024 else { throw NearbyError.capacity }
        queuedBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.queuedBytes -= data.count
                if error != nil { self.close() }
            }
        })
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
        onReady = nil
        onData = nil
        onClose = nil
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty { self.onData?(data) }
                if complete || error != nil { self.close() } else { self.receive() }
            }
        }
    }
}
