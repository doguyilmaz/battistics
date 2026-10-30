import Foundation

/// A wall-clock bound on work, including a service that ignores task cancellation.
/// Unlike a task-group race, returning does not wait for the losing task to finish.
public enum RemoteDeadline {
    public enum Failure: Error, Sendable {
        case exceeded
    }

    public static func perform<Value: Sendable>(
        until deadline: ContinuousClock.Instant,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw Failure.exceeded }

        let stream = AsyncThrowingStream<Value, Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let work = Task {
                do {
                    try Task.checkCancellation()
                    continuation.yield(try await operation())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let timer = Task {
                do { try await Task.sleep(until: deadline, clock: .continuous) }
                catch { return }
                continuation.finish(throwing: Failure.exceeded)
            }
            // AsyncThrowingStream arbitrates completion, timeout and cancellation
            // exactly once. CloudKit operations install their own cancellation handler.
            continuation.onTermination = { _ in
                work.cancel()
                timer.cancel()
            }
        }
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw Failure.exceeded }
        return value
    }
}
