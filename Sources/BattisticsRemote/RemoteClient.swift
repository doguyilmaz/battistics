import Foundation
import Network

/// One request, one reply, then the connection closes.
public enum RemoteClient {
    public enum Failure: Error, Sendable { case unreachable, timedOut, malformed }

    public static func send(_ request: RemoteRequest, to pairing: RemotePairing,
                            timeout: Duration = .seconds(8)) async throws -> RemoteReply {
        guard let port = NWEndpoint.Port(rawValue: pairing.port) else { throw Failure.unreachable }
        let payload = try RemoteWire.encode(request)
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(host: .init(pairing.host), port: port, using: parameters)
        let exchange = Exchange()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exchange.begin(continuation, connection: connection)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: payload, completion: .contentProcessed { error in
                            if error != nil { exchange.finish(.failure(Failure.unreachable)) }
                        })
                        receive(on: connection, into: Data(), exchange: exchange)
                    case .failed, .waiting:
                        exchange.finish(.failure(Failure.unreachable))
                    default: break
                    }
                }
                connection.start(queue: exchange.queue)
                exchange.queue.asyncAfter(deadline: .now() + timeout.timeInterval) {
                    exchange.finish(.failure(Failure.timedOut))
                }
            }
        } onCancel: {
            exchange.finish(.failure(CancellationError()))
        }
    }

    private static func receive(on connection: NWConnection, into buffer: Data, exchange: Exchange) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: RemoteWire.maximumBytes) { data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.contains(10) || complete {
                do { exchange.finish(.success(try RemoteWire.decode(RemoteReply.self, from: buffer))) }
                catch { exchange.finish(.failure(Failure.malformed)) }
            } else if error != nil || buffer.count >= RemoteWire.maximumBytes {
                exchange.finish(.failure(error == nil ? Failure.malformed : Failure.unreachable))
            } else {
                receive(on: connection, into: buffer, exchange: exchange)
            }
        }
    }

    /// Resumes the continuation exactly once and always cancels the connection.
    private final class Exchange: @unchecked Sendable {
        let queue = DispatchQueue(label: "com.doguyilmaz.Battistics.remote.client")
        private let lock = NSLock()
        private var continuation: CheckedContinuation<RemoteReply, Error>?
        private var connection: NWConnection?

        func begin(_ continuation: CheckedContinuation<RemoteReply, Error>, connection: NWConnection) {
            lock.withLock {
                self.continuation = continuation
                self.connection = connection
            }
        }

        func finish(_ result: Result<RemoteReply, Error>) {
            let (continuation, connection) = lock.withLock {
                defer { self.continuation = nil; self.connection = nil }
                return (self.continuation, self.connection)
            }
            connection?.cancel()
            continuation?.resume(with: result)
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
