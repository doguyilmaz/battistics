import Darwin
import Foundation

/// Socket readiness waits are confined to a dedicated serial queue, never the
/// cooperative executor. Every request has a five-second absolute timeout.
/// A failed exchange closes the connection and is never automatically retried.
public final class LocalAutomationClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.doguyilmaz.Battistics.automation.client")
    private let endpoint: LocalAutomationEndpoint
    private var fd: Int32 = -1
    public init(endpoint: LocalAutomationEndpoint = .standard) { self.endpoint = endpoint }

    deinit { if fd >= 0 { Darwin.close(fd) } }

    public func request(_ request: AutomationRequest) async throws -> AutomationReply {
        let data = try JSONEncoder().encode(request) + Data([10])
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.exchange(data, timeout: request.operation == .start ? 15 : 5)) }
                catch { self.disconnect(); continuation.resume(throwing: error) }
            }
        }
    }

    public func close() async {
        await withCheckedContinuation { continuation in
            queue.async { self.disconnect(); continuation.resume() }
        }
    }

    private func disconnect() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    private func connectIfNeeded() throws {
        guard fd < 0 else { return }
        try endpoint.validateDirectory(create: false)
        var info = stat()
        guard lstat(endpoint.socketPath, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFSOCK, info.st_mode & 0o077 == 0 else { throw POSIXError(.EACCES) }
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.EMFILE) }
        do {
            try LocalAutomationEndpoint.configure(socketFD, nonblocking: true)
            var address = try endpoint.address()
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw POSIXError(.ECONNREFUSED) }
                var descriptor = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
                guard poll(&descriptor, 1, 5_000) > 0 else { throw POSIXError(.ETIMEDOUT) }
                var error: Int32 = 0
                var size = socklen_t(MemoryLayout.size(ofValue: error))
                guard getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw POSIXError(.ECONNREFUSED) }
            }
            try LocalAutomationEndpoint.verifyPeer(socketFD)
            fd = socketFD
        } catch { Darwin.close(socketFD); throw error }
    }

    /// A closed-lid start waits on the power helper for up to 10 seconds.
    private func exchange(_ data: Data, timeout seconds: UInt64) throws -> AutomationReply {
        guard data.count <= 16_384 else { throw POSIXError(.EMSGSIZE) }
        let deadline = DispatchTime.now().uptimeNanoseconds + seconds * 1_000_000_000
        try connectIfNeeded()
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try waitForIO(Int16(POLLOUT), until: deadline)
                let count = send(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        var response = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while response.count < 16_384 {
            try waitForIO(Int16(POLLIN), until: deadline)
            let count = recv(fd, &bytes, bytes.count, 0)
            if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
            guard count > 0 else { throw POSIXError(.ECONNRESET) }
            response.append(contentsOf: bytes.prefix(count))
            guard response.count <= 16_384 else { throw POSIXError(.EMSGSIZE) }
            if response.contains(10) { return try JSONDecoder().decode(AutomationReply.self, from: response) }
        }
        throw POSIXError(.EMSGSIZE)
    }

    private func waitForIO(_ events: Int16, until deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw POSIXError(.ETIMEDOUT) }
            let milliseconds = Int32(min(5_000, (deadline - now + 999_999) / 1_000_000))
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, milliseconds)
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { throw POSIXError(.ETIMEDOUT) }
            guard descriptor.revents & Int16(POLLERR | POLLNVAL) == 0 else { throw POSIXError(.ECONNRESET) }
            return
        }
    }
}
