import Foundation

/// Serial-owner state machine for a privileged, renewable sleep override.
/// Journal hooks must persist the original setting before any mutation.
public final class LidSleepLease {
    private var owner: UUID?
    private var deadline: Date?
    private var original: Bool?
    private let read: () throws -> Bool
    private let write: (Bool) throws -> Void
    private let save: (Bool) throws -> Void
    private let clear: () throws -> Void

    public init(read: @escaping () throws -> Bool, write: @escaping (Bool) throws -> Void,
                save: @escaping (Bool) throws -> Void, clear: @escaping () throws -> Void) {
        self.read = read
        self.write = write
        self.save = save
        self.clear = clear
    }

    public func recover(original: Bool) throws {
        self.original = original
        try restore()
    }

    public func renew(owner: UUID, now: Date = Date()) throws {
        if let current = self.owner, current != owner { throw CocoaError(.fileLocking) }
        if self.owner == nil {
            // Retry a previous failed restoration before accepting a session.
            if original != nil { try restore() }
            let previous = try read()
            try save(previous)
            original = previous
            do { try write(true) } catch {
                try? restore()
                throw error
            }
            self.owner = owner
        }
        deadline = now.addingTimeInterval(45)
    }

    public func release(owner: UUID) throws {
        guard self.owner == owner else { return }
        try restore()
    }

    public func expire(now: Date = Date()) throws {
        if let deadline, now >= deadline { try restore() }
        else if owner == nil, original != nil { try restore() }
    }

    private func restore() throws {
        guard let original else { return }
        try write(original)
        try clear()
        self.original = nil
        owner = nil
        deadline = nil
    }
}
