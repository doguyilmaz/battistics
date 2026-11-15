import Foundation

@MainActor
final class NearbyBLELink: NearbyLink {
    let id: UUID
    let kind = RemoteRoute.Kind.bluetooth
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onAuthenticated: (() -> Void)?
    var authenticated = false { didSet { if authenticated { onAuthenticated?() } } }
    private let sender: (Data) throws -> Void
    private let closer: () -> Void
    private var closed = false

    init(id: UUID, send: @escaping (Data) throws -> Void, close: @escaping () -> Void) {
        self.id = id
        sender = send
        closer = close
    }

    func send(_ data: Data) throws {
        guard !closed else { throw NearbyError.unavailable }
        try sender(data)
    }

    func received(_ data: Data) { if !closed { onData?(data) } }

    func close() {
        guard !closed else { return }
        closed = true
        closer()
        onClose?()
        onData = nil
        onClose = nil
        onAuthenticated = nil
    }
}
