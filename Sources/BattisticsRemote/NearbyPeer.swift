import Foundation

@MainActor
final class NearbyPeer {
    let link: any NearbyLink
    let credential: NearbyCredential
    var onReady: (() -> Void)?
    var onMessage: ((NearbyMessage) -> Void)?
    var onClosed: (() -> Void)?
    private var session: NearbySession
    private var frames = NearbyFrameBuffer()
    private var closed = false
    private let clock: () -> ContinuousClock.Instant
    private var lastReceived: ContinuousClock.Instant
    private var handshakeDeadline: Task<Void, Never>?
    private var pending: [UUID: CheckedContinuation<RemoteStatus, Error>] = [:]

    var authenticated: Bool { !closed && session.authenticated }
    var healthy: Bool { authenticated && lastReceived.duration(to: clock()) < .seconds(90) }

    init(link: any NearbyLink, credential: NearbyCredential, server: Bool,
         clock: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.link = link
        self.credential = credential
        self.clock = clock
        lastReceived = clock()
        session = NearbySession(credential: credential, server: server)
        link.onData = { [weak self] data in self?.receive(data) }
        link.onClose = { [weak self] in self?.close() }
        handshakeDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.close()
        }
    }

    func begin() {
        do { try link.send(NearbyFrameBuffer.frame(session.begin())) } catch { close() }
    }

    func send(_ message: NearbyMessage) throws {
        do { try link.send(NearbyFrameBuffer.frame(session.seal(message))) }
        catch { close(); throw error }
    }

    func request(_ command: RemoteRequest, until deadline: ContinuousClock.Instant) async throws -> RemoteStatus {
        do {
            return try await RemoteDeadline.perform(until: deadline) {
                try await self.enqueue(command)
            }
        } catch { close(); throw error }
    }

    func close() {
        guard !closed else { return }
        closed = true
        handshakeDeadline?.cancel()
        let replies = pending.values
        pending = [:]
        for reply in replies { reply.resume(throwing: NearbyError.unavailable) }
        link.close()
        onClosed?()
        onClosed = nil
        onReady = nil
        onMessage = nil
    }

    private func enqueue(_ command: RemoteRequest) async throws -> RemoteStatus {
        try Task.checkCancellation()
        guard healthy, pending.count < 8 else { throw NearbyError.unavailable }
        let id = UUID()
        return try await withCheckedThrowingContinuation { reply in
            pending[id] = reply
            do { try send(.command(id: id, request: command)) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
        }
    }

    private func receive(_ data: Data) {
        guard !closed else { return }
        do {
            for frame in try frames.append(data) {
                let authenticated = session.authenticated
                let received = try session.receive(frame)
                if let response = received.response { try link.send(NearbyFrameBuffer.frame(response)) }
                if session.authenticated {
                    lastReceived = clock()
                    if !authenticated {
                        handshakeDeadline?.cancel()
                        (link as? NearbyBLELink)?.authenticated = true
                        onReady?()
                    }
                }
                if let message = received.message {
                    if case .status(let id?, let status) = message {
                        try send(.acknowledged(id))
                        pending.removeValue(forKey: id)?.resume(returning: status)
                    }
                    onMessage?(message)
                }
            }
        } catch { close() }
    }
}
