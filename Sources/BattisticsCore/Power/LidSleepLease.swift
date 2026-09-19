import Foundation

/// Serial-owner state machine. Only an explicit acquisition may enable sleep
/// suppression; a renewal can neither acquire nor revive a terminal session.
public final class LidSleepLease {
    private struct Active {
        let owner: UUID
        let session: UUID
        var journal: LidSleepLeaseJournal
        var deadline: Date
    }
    private struct Terminal {
        let owner: UUID?
        let result: LidSleepLeaseResult
    }

    private var active: Active?
    private var disconnectedOwners: Set<UUID> = []
    private var terminal: [UUID: Terminal] = [:]
    private var blocked = false
    private let read: () throws -> Bool
    private let write: (Bool) throws -> Void
    private let save: (LidSleepLeaseJournal) throws -> Void
    private let clear: () throws -> Void

    public init(read: @escaping () throws -> Bool, write: @escaping (Bool) throws -> Void,
                save: @escaping (LidSleepLeaseJournal) throws -> Void,
                clear: @escaping () throws -> Void) {
        self.read = read
        self.write = write
        self.save = save
        self.clear = clear
    }

    /// The serial owner can arm one deadline instead of polling while idle.
    public var expirationDate: Date? { active?.deadline }

    public func acquire(owner: UUID, session: UUID, now: Date = Date()) -> LidSleepLeaseResult {
        guard !blocked else { return .failed }
        guard !disconnectedOwners.contains(owner) else { return .rejected }
        guard terminal[session] == nil else { return .inactive }
        guard active == nil else { return .rejected }
        let original: Bool
        do { original = try read() } catch {
            terminal[session] = Terminal(owner: owner, result: .unavailable)
            return .unavailable
        }
        var record = LidSleepLeaseJournal(original: original, session: session, phase: .prepared)
        do { try save(record) } catch {
            terminal[session] = Terminal(owner: owner, result: .failed)
            // A failed atomic write may still have left a record. Disarm it.
            _ = abandon(record)
            return .failed
        }
        active = Active(owner: owner, session: session, journal: record,
                        deadline: now.addingTimeInterval(45))
        // Borrow an existing override without claiming or rewriting its value.
        if !original {
            // Journaling takes time. If another app enabled the override since
            // our initial snapshot, it owns that value; do not claim it.
            do {
                guard try !read() else { return finish(result: .ownershipLost) }
            } catch { return finish(result: .unavailable) }
            do { try write(true) } catch {
                // A timed-out command may have mutated the setting. Do not guess
                // whether a subsequent value belongs to this failed operation.
                return finish(result: .failed)
            }
        }
        do {
            guard try read() else { return finish(result: .ownershipLost) }
        } catch { return finish(result: .unavailable) }
        // A crash before this promotion leaves an uncertain prepared record,
        // which recovery retires without touching the system setting.
        record.phase = .active
        do { try save(record) } catch { return finish(result: .failed) }
        active?.journal = record
        return .success
    }

    public func renew(owner: UUID, session: UUID, now: Date = Date()) -> LidSleepLeaseResult {
        guard let current = active, current.session == session else {
            return terminalResult(owner: owner, session: session)
        }
        guard current.owner == owner else { return .rejected }
        guard now < current.deadline else {
            let result = restore()
            return result == .success ? .inactive : result
        }
        do {
            guard try read() else { return finish(result: .ownershipLost) }
        } catch { return finish(result: .unavailable) }
        active?.deadline = now.addingTimeInterval(45)
        return .success
    }

    public func release(owner: UUID, session: UUID) -> LidSleepLeaseResult {
        guard let current = active, current.session == session else {
            return terminalResult(owner: owner, session: session)
        }
        guard current.owner == owner else { return .rejected }
        return restore()
    }

    public func disconnected(owner: UUID) -> LidSleepLeaseResult {
        // An invalidation can reach the serial queue before a concurrently
        // delivered acquire request. That dead endpoint cannot create a lease.
        disconnectedOwners.insert(owner)
        guard let current = active, current.owner == owner else { return .inactive }
        return restore()
    }

    /// Idle ticks perform no reads, writes, or journal operations.
    public func expire(now: Date = Date()) -> LidSleepLeaseResult {
        guard let current = active, now >= current.deadline else { return .inactive }
        return restore()
    }

    public func recover(journal: LidSleepLeaseJournal) -> LidSleepLeaseResult {
        guard active == nil, !blocked else { return .rejected }
        if let session = journal.session, let ended = terminal[session] {
            return ended.result
        }
        let result = recoverOnce(journal: journal)
        if let session = journal.session {
            terminal[session] = Terminal(owner: nil, result: result == .success ? .inactive : result)
        }
        return result
    }

    private func recoverOnce(journal: LidSleepLeaseJournal) -> LidSleepLeaseResult {
        guard journal.phase == .active else {
            // Prepared means the acquisition never reached durable verification.
            // No setting read or rollback can establish ownership afterward.
            return abandon(journal) ? .inactive : .failed
        }
        let current: Bool
        do { current = try read() } catch {
            return abandon(journal) ? .unavailable : .failed
        }
        guard current else {
            return abandon(journal) ? .ownershipLost : .failed
        }
        guard abandon(journal) else { return .failed }
        // Original true represents a borrowed override, never a rollback write.
        guard !journal.original else { return .success }
        do {
            guard try read() else { return .ownershipLost }
        } catch { return .unavailable }
        do { try write(false) } catch { return .failed }
        do { return try read() ? .failed : .success } catch { return .unavailable }
    }

    private func terminalResult(owner: UUID, session: UUID) -> LidSleepLeaseResult {
        guard let ended = terminal[session] else { return .inactive }
        guard ended.owner == nil || ended.owner == owner else { return .rejected }
        return ended.result
    }

    private func restore() -> LidSleepLeaseResult {
        guard let current = active else { return .inactive }
        do {
            guard try read() else { return finish(result: .ownershipLost) }
        } catch { return finish(result: .unavailable) }
        // Consume rollback authorization before writing. A crash, timeout, or
        // failed deletion must never replay an already attempted rollback.
        guard finish(result: .inactive) != .failed else {
            return remember(.failed, for: current)
        }
        guard !current.journal.original else { return .success }
        do {
            guard try read() else { return remember(.ownershipLost, for: current) }
        } catch { return remember(.unavailable, for: current) }
        do { try write(false) } catch { return remember(.failed, for: current) }
        do {
            guard try !read() else { return remember(.failed, for: current) }
        } catch { return remember(.unavailable, for: current) }
        return .success
    }

    private func remember(_ result: LidSleepLeaseResult, for current: Active) -> LidSleepLeaseResult {
        terminal[current.session] = Terminal(owner: current.owner, result: result)
        return result
    }

    private func finish(result: LidSleepLeaseResult) -> LidSleepLeaseResult {
        guard let current = active else { return .inactive }
        active = nil
        terminal[current.session] = Terminal(owner: current.owner, result: result)
        return abandon(current.journal) ? result : remember(.failed, for: current)
    }

    /// Prefer a durable terminal record. If that fails, removal is a safe
    /// fallback. If both fail, prohibit all further acquisitions in this process.
    private func abandon(_ journal: LidSleepLeaseJournal) -> Bool {
        var ended = journal
        ended.phase = .abandoned
        do {
            try save(ended)
            try? clear()
            return true
        } catch {
            do { try clear(); return true } catch {
                blocked = true
                return false
            }
        }
    }
}
