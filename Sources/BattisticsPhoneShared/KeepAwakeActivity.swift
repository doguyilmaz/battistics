import ActivityKit
import BattisticsRemote
import Foundation

struct KeepAwakeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: RemoteStatus.Mode
        var startedAt: Date
        var deadline: Date
        var batteryPercent: Int?
    }

    var macName: String
}
