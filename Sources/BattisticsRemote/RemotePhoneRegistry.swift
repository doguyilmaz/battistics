import Foundation

/// Bounded, encrypted per-Mac roster. Conflict retries merge independent phones.
public struct RemotePhoneRegistry: Codable, Equatable, Sendable {
    public private(set) var phones: [RemotePhoneInfo] = []
    public init() {}

    public mutating func record(_ phone: RemotePhoneInfo, at now: Date = .now) {
        guard phone.isValid, phone.seenAt <= now.addingTimeInterval(300),
              phone.seenAt > now.addingTimeInterval(-30 * 86400) else { return }
        var retained = phones.filter {
            $0.isValid && $0.seenAt > now.addingTimeInterval(-30 * 86400) && $0.seenAt <= now.addingTimeInterval(300)
        }
        if let old = retained.first(where: { $0.id == phone.id }), old.seenAt > phone.seenAt { return }
        retained.removeAll { $0.id == phone.id }
        retained.append(phone)
        phones = Array(retained.sorted { $0.seenAt == $1.seenAt ? $0.id < $1.id : $0.seenAt > $1.seenAt }.prefix(8))
    }
}
