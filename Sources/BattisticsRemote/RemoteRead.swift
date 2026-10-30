import Foundation

/// One bounded read shared by callers. Cancelling a waiter does not restart the
/// network request; its completed answer stays available until a waiter consumes it.
public actor RemoteRead<Value: Sendable> {
    private let timeout: Duration
    private let operation: @Sendable () async throws -> Value
    private var pending: (id: UUID, task: Task<Value, Error>)?

    public init(timeout: Duration = .seconds(45), operation: @escaping @Sendable () async throws -> Value) {
        self.timeout = timeout
        self.operation = operation
    }

    public func value() async throws -> Value {
        try Task.checkCancellation()
        let read: (id: UUID, task: Task<Value, Error>)
        if let pending {
            read = pending
        } else {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            let operation = operation
            read = (UUID(), Task { try await RemoteDeadline.perform(until: deadline, operation: operation) })
            pending = read
        }
        do {
            // This bound belongs to the waiter, not to the retained result. A
            // result completed while the app was inactive must still be usable.
            let value = try await RemoteDeadline.perform(until: .now.advanced(by: timeout)) {
                try await read.task.value
            }
            if pending?.id == read.id { pending = nil }
            return value
        } catch {
            if !Task.isCancelled, pending?.id == read.id { pending = nil }
            throw error
        }
    }
}
