import Foundation

/// Re-enabling sharing waits for an earlier destructive withdrawal attempt.
@MainActor
final class RemoteWithdrawal {
    private var pending: Task<Void, Never>?
    private var publications: [UUID: Task<Void, Error>] = [:]

    /// Track only the SDK write, rather than a setup/publication task that may
    /// itself be waiting for withdrawal. Deletion must follow every old write.
    func publish(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let id = UUID()
        let work = Task { try await operation() }
        publications[id] = work
        defer { publications[id] = nil }
        try await work.value
    }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = pending
        let writes = Array(publications.values)
        let next = Task {
            await previous?.value
            for write in writes { _ = await write.result }
            await operation()
        }
        pending = next
        await next.value
        if pending == next { pending = nil }
    }

    func settle() async {
        while let previous = pending {
            await previous.value
            if pending == previous { return }
        }
    }
}
