import Foundation

/// Admission is persisted before a side effect. An interrupted operation is never
/// automatically replayed after relaunch; its outcome is explicitly uncertain.
public actor RemoteCommandJournal {
    public enum Admission: Sendable {
        case execute
        case completed(RemoteStatus.CommandResult)
        case uncertain
    }

    private struct Entry: Codable {
        var request: RemoteRequest
        var acceptedAt: Date
        var result: RemoteStatus.CommandResult?
    }

    private struct State: Codable {
        var revision: UInt64 = 0
        var commands: [String: Entry] = [:]
    }

    private let url: URL
    private var state = State()
    private var loaded = false

    public init(url: URL) { self.url = url }

    public func claim(_ request: RemoteRequest, at now: Date = .now) throws -> Admission {
        try load()
        let age = now.timeIntervalSince(request.sentAt)
        guard age >= -30, age < RemoteRequest.lifetime,
              try RemoteWire.encode(request).count <= 4096 else { throw NearbyError.staleRequest }
        if let entry = state.commands[request.id] {
            guard entry.request.isSameCommand(as: request) else { throw NearbyError.commandCollision }
            return entry.result.map(Admission.completed) ?? .uncertain
        }
        state.commands = state.commands.filter { now.timeIntervalSince($0.value.acceptedAt) < 2 * RemoteRequest.lifetime }
        guard state.commands.count < 128 else { throw NearbyError.capacity }
        let previous = state
        state.commands[request.id] = Entry(request: request, acceptedAt: now)
        do { try save() } catch { state = previous; throw error }
        return .execute
    }

    public func complete(_ result: RemoteStatus.CommandResult) throws {
        try load()
        guard state.commands[result.id] != nil else { throw NearbyError.uncertainCommand }
        let previous = state
        state.commands[result.id]?.result = result
        do { try save() } catch { state = previous; throw error }
    }

    public func nextRevision() throws -> UInt64 {
        try load()
        guard state.revision < UInt64.max else { throw NearbyError.capacity }
        let previous = state
        state.revision += 1
        do { try save() } catch { state = previous; throw error }
        return state.revision
    }

    private func load() throws {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count <= 1024 * 1024 else { throw NearbyError.capacity }
            state = try RemoteWire.decode(State.self, from: data)
        }
        loaded = true
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RemoteWire.encode(state).write(to: url, options: [.atomic])
    }
}
