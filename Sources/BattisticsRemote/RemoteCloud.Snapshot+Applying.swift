import Foundation

extension RemoteCloud.Snapshot {
    /// The phone needs a whole list of Macs, not just the ones changed in this
    /// fetch. Only a full read or an explicit deletion can remove a saved Mac.
    func applying(_ delta: Self) -> Self {
        if delta.isFull { return delta }
        var full = self
        full.requestedAt = delta.requestedAt
        full.isFull = true
        let removed = delta.removedRecords.union(delta.removedStatuses)
        for id in removed {
            full.statuses[id] = nil
            full.events[id] = nil
            full.unreadable.remove(id)
        }
        for id in delta.unreadable { full.statuses[id] = nil }
        full.unreadable.formUnion(delta.unreadable)
        for (id, status) in delta.statuses {
            full.statuses[id] = status
            full.unreadable.remove(id)
        }
        var commands = Dictionary(full.commands.map { ($0.recordName, $0) }, uniquingKeysWith: { _, new in new })
        for id in removed { commands[id] = nil }
        for command in delta.commands { commands[command.recordName] = command }
        full.commands = Array(commands.values)
        full.events.merge(delta.events) { $1 }
        full.removedRecords = delta.removedRecords
        full.removedStatuses = delta.removedStatuses
        return full
    }
}
