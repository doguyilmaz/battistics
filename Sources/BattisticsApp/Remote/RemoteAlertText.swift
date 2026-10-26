import BattisticsCore
import BattisticsRemote
import Foundation

extension RemoteAlert {
    /// What the phone shows straight from the push, in this Mac's language.
    var pushText: (title: String, body: String)? {
        switch self {
        case .sessionEnded(let reason):
            (String(localized: "Keep Awake ended"), reason.map(Self.text) ?? String(localized: "The Mac can sleep again."))
        case .batteryLow(let percent):
            (String(localized: "Mac battery low"),
             String(localized: "Battery is at \(Formatting.percent(Double(percent))). Connect power if the Mac must keep running."))
        case .batteryRunsOut(let minutes):
            (String(localized: "Battery runs out first"),
             String(localized: "The battery lasts about \(Formatting.duration(minutes: minutes)), less than the Keep Awake session."))
        case .unpluggedWithoutHotspot:
            (String(localized: "Mac unplugged on Wi‑Fi"),
             String(localized: "Turn on Personal Hotspot before the Mac goes in a bag, so its tasks stay online."))
        case .closedLidWithoutHotspot:
            (String(localized: "Lid closed without Hotspot"),
             String(localized: "Connect the Mac to Personal Hotspot if you are taking it with you."))
        case .runningHot:
            (String(localized: "Mac is running hot"),
             String(localized: "Open the lid and keep the vents clear, or stop Keep Awake."))
        case .bagReady:
            (String(localized: "Bag Ready"),
             String(localized: "On Personal Hotspot. You can close the lid and the Mac stays online."))
        case .sleptDuringSession:
            (String(localized: "Mac went to sleep"),
             String(localized: "Keep Awake was on. To keep a closed Mac awake, use Lid Closed."))
        case .chargeReached, .unreachable:
            nil
        }
    }

    private static func text(_ reason: RemoteStatus.EndReason) -> String {
        switch reason {
        case .timer: String(localized: "The time you set is up.")
        case .user: String(localized: "Stopped on the Mac.")
        case .phone: String(localized: "Stopped from iPhone.")
        case .battery: String(localized: "Battery protection stopped it.")
        case .thermal: String(localized: "Heat protection stopped it.")
        case .client: String(localized: "The task finished.")
        case .failure: String(localized: "macOS ended it.")
        }
    }
}
