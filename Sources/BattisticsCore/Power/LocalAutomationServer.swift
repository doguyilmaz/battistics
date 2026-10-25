import Darwin
import Foundation

/// All socket state belongs to `queue`. Main-actor callbacks arrive in socket
/// event order; app code checks the connection registry again after suspension.
public final class LocalAutomationServer: @unchecked Sendable {
    public typealias Handler = @MainActor @Sendable (UUID, AutomationRequest) async -> AutomationReply
    private final class Client: @unchecked Sendable {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = Data()
        var pending = false
        init(fd: Int32, source: DispatchSourceRead) { self.fd = fd; self.source = source }
    }
    private let queue = DispatchQueue(label: "com.doguyilmaz.Battistics.automation.server")
    private let endpoint: LocalAutomationEndpoint
    private let handler: Handler
    private let connected: @MainActor @Sendable (UUID) -> Void
    private let disconnected: @MainActor @Sendable (UUID) -> Void
    private var listener: DispatchSourceRead?
    private var clients: [UUID: Client] = [:]
    private var lockFD: Int32 = -1
    private static let maximumFrameBytes = 16_384

    public init(endpoint: LocalAutomationEndpoint = .standard,
                connected: @escaping @MainActor @Sendable (UUID) -> Void,
                disconnected: @escaping @MainActor @Sendable (UUID) -> Void,
                handler: @escaping Handler) {
        self.endpoint = endpoint
        self.connected = connected
        self.disconnected = disconnected
        self.handler = handler
    }

    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.listen(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                for id in Array(self.clients.keys) { self.closeClient(id) }
                guard let listener = self.listener else { continuation.resume(); return }
                self.listener = nil
                let fd = Int32(listener.handle)
                let lockFD = self.lockFD
                self.lockFD = -1
                let endpoint = self.endpoint
                listener.setCancelHandler {
                    Darwin.close(fd)
                    unlink(endpoint.socketPath)
                    flock(lockFD, LOCK_UN)
                    Darwin.close(lockFD)
                    continuation.resume()
                }
                listener.cancel()
            }
        }
    }

    private func listen() throws {
        guard listener == nil else { return }
        try endpoint.validateDirectory(create: true)
        let lock = open(endpoint.lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw POSIXError(.EACCES) }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lock)
            throw POSIXError(.EADDRINUSE)
        }
        var ownsPath = false
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        do {
            guard fd >= 0 else { throw POSIXError(.EMFILE) }
            try LocalAutomationEndpoint.configure(fd, nonblocking: true)
            if lstat(endpoint.socketPath, &info) == 0 {
                guard info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw POSIXError(.EACCES) }
                guard unlink(endpoint.socketPath) == 0 else { throw POSIXError(.EACCES) }
            } else if errno != ENOENT { throw POSIXError(.EACCES) }
            var address = try endpoint.address()
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw POSIXError(.EADDRINUSE) }
            ownsPath = true
            guard chmod(endpoint.socketPath, 0o600) == 0, Darwin.listen(fd, 8) == 0 else { throw POSIXError(.EACCES) }
            lockFD = lock
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptClients(fd) }
            listener = source
            source.resume()
        } catch {
            if fd >= 0 { Darwin.close(fd) }
            if ownsPath { unlink(endpoint.socketPath) }
            flock(lock, LOCK_UN)
            Darwin.close(lock)
            throw error
        }
    }

    private func acceptClients(_ listenerFD: Int32) {
        while true {
            let fd = accept(listenerFD, nil, nil)
            guard fd >= 0 else { return }
            do {
                guard clients.count < 8 else { throw POSIXError(.EMFILE) }
                try LocalAutomationEndpoint.verifyPeer(fd)
                try LocalAutomationEndpoint.configure(fd, nonblocking: true)
                let id = UUID()
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
                clients[id] = Client(fd: fd, source: source)
                source.setEventHandler { [weak self] in self?.readClient(id) }
                source.setCancelHandler { Darwin.close(fd) }
                DispatchQueue.main.async { self.connected(id) }
                source.resume()
            } catch { Darwin.close(fd) }
        }
    }

    private func readClient(_ id: UUID) {
        guard let client = clients[id] else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(client.fd, &bytes, bytes.count, 0)
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
            guard count > 0, !client.pending else { closeClient(id); return }
            client.buffer.append(contentsOf: bytes.prefix(count))
            guard client.buffer.count <= Self.maximumFrameBytes else { closeClient(id); return }
            if let newline = client.buffer.firstIndex(of: 10) {
                guard newline == client.buffer.index(before: client.buffer.endIndex),
                      let request = try? JSONDecoder().decode(AutomationRequest.self, from: client.buffer)
                else { closeClient(id); return }
                client.buffer.removeAll(keepingCapacity: true)
                client.pending = true
                DispatchQueue.main.async {
                    Task { @MainActor in
                        let reply = await self.handler(id, request)
                        self.queue.async { self.respond(reply, to: id) }
                    }
                }
                // Keep watching EOF during an async start. Pipelining is not
                // supported by this private IPC (the MCP transport handles it).
                return
            }
        }
    }

    private func respond(_ reply: AutomationReply, to id: UUID) {
        guard let client = clients[id], var data = try? JSONEncoder().encode(reply),
              data.count < Self.maximumFrameBytes else { closeClient(id); return }
        data.append(10)
        let sent = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = send(client.fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        if sent { client.pending = false } else { closeClient(id) }
    }

    private func closeClient(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.source.cancel()
        DispatchQueue.main.async { self.disconnected(id) }
    }
}
