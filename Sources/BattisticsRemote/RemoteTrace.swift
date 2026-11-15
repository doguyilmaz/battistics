import CryptoKit
import Foundation
import os

/// Opt-in Debug-only milestones for a physical background-delivery trial.
/// Logs contain timestamps, revisions and a hashed identifier, never payloads.
public enum RemoteTrace: String, Sendable {
    case cloudPublished, cloudReceived, nearbyReceived, applied, activityCreated, activitySubmitted

    private static let logger = Logger(subsystem: "com.doguyilmaz.Battistics.Remote", category: "DeliveryTrial")

    public static func record(_ stage: Self, macID: String, status: RemoteStatus, appState: Int? = nil) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-remote-delivery-trace") else { return }
        let tag = SHA256.hash(data: Data(macID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        logger.notice("delivery_trial stage=\(stage.rawValue, privacy: .public) mac=\(tag, privacy: .public) revision=\(status.revision ?? 0) sample=\(status.readAt.timeIntervalSince1970) observed=\(Date.now.timeIntervalSince1970) appState=\(appState ?? -1)")
        #endif
    }
}
