import Foundation

/// Discovery is a hint, not trust. Failed candidates must release their slots.
struct NearbyCandidates: Sendable {
    enum Failure { case disconnected, setup, rejected }
    private struct Entry: Sendable {
        var macID: String
        var trusted = false
        var failures = 0
    }
    private var entries: [UUID: Entry] = [:]

    mutating func admit(_ id: UUID, macID: String) -> Bool {
        if entries[id]?.macID == macID { return true }
        guard entries[id] != nil || entries.count < 8 else { return false }
        let pending = entries.filter { $0.key != id && $0.value.macID == macID && !$0.value.trusted }.count
        guard pending < 2 else { return false }
        entries[id] = Entry(macID: macID)
        return true
    }

    mutating func authenticate(_ id: UUID) {
        entries[id]?.trusted = true
        entries[id]?.failures = 0
    }

    /// True means keep a bounded/native pending reconnect for this candidate.
    mutating func failed(_ id: UUID, reason: Failure) -> Bool {
        guard var entry = entries[id] else { return false }
        if case .disconnected = reason, entry.trusted { return true }
        if case .setup = reason, entry.failures < 2 {
            entry.failures += 1
            entries[id] = entry
            return true
        }
        entries[id] = nil
        return false
    }

    mutating func remove(_ id: UUID) { entries[id] = nil }
    mutating func clear() { entries = [:] }
}
