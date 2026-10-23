import BattisticsRemote
import Foundation

/// The selected Mac's latest reading, written by the app for its widgets.
struct SharedSnapshot: Codable, Equatable {
    var macName: String
    var status: RemoteStatus?
    var lastSeen: Date?
    var reachable: Bool

    static let group = "group.com.doguyilmaz.Battistics.Remote"
    private static let key = "snapshot"

    static func load() -> SharedSnapshot? {
        UserDefaults(suiteName: group)?.data(forKey: key).flatMap { try? RemoteWire.decode(Self.self, from: $0) }
    }

    func save() {
        UserDefaults(suiteName: Self.group)?.set(try? RemoteWire.encode(self), forKey: Self.key)
    }

    static func clear() {
        UserDefaults(suiteName: group)?.removeObject(forKey: key)
    }
}
