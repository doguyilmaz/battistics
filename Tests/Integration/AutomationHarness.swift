import AppKit
import BattisticsCore
import SwiftUI

extension Notification.Name {
    static let battisticsSelectPane = Notification.Name("battisticsSelectPane")
}

/// Runs with a separate bundle identifier and temporary socket. It acquires
/// short-lived idle/display assertions only; it never installs a helper or
/// enables closed-lid mode on the development Mac.
@main
@MainActor
struct AutomationHarness {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.setVolatileDomain([
            Prefs.keepAwakeWarnOnLowBattery: false, Prefs.keepAwakeStopOnLowBattery: false,
            Prefs.keepAwakeStopOnThermalPressure: false, Prefs.automationClosedLidAllowed: false,
            Prefs.powerSamplingEnabled: false, Prefs.hasSeenTour: true,
        ], forName: UserDefaults.argumentDomain)
        Prefs.registerDefaults()
        let helper = PowerHelperClient()
        let awake = KeepAwakeModel(helper: helper)
        let endpoint = LocalAutomationEndpoint(directory: "/private/tmp/battistics-app-test-\(UUID())")
        let automation = AutomationModel(awake: awake, helper: helper, endpoint: endpoint, initiallyEnabled: true)
        try await eventually { automation.isListening }
        let first = LocalAutomationClient(endpoint: endpoint), other = LocalAutomationClient(endpoint: endpoint)

        let invalid = try await first.request(.init(.start, name: "Unbounded", durationMinutes: 0))
        precondition(invalid.error?.code == "invalid_request" && !awake.isActive)
        let closedLid = try await first.request(.init(.start, name: "Closed lid", mode: "lidClosed", durationMinutes: 15))
        precondition(closedLid.error?.code == "closed_lid_not_allowed" && !awake.isActive)

        let start = try await first.request(.init(.start, name: "Build the project", durationMinutes: 15))
        let id = try require(start.status?.sessionID)
        precondition(awake.isActive && awake.displayedMode == .displayMaySleep)
        precondition(automation.activeTaskName == "Build the project")
        let deadline = awake.session?.deadline
        let heartbeat = try await first.request(.init(.heartbeat, sessionID: id))
        precondition(heartbeat.status?.sessionID == id && awake.session?.deadline == deadline)
        let foreignStatus = try await other.request(.init(.status))
        precondition(foreignStatus.status?.owner == .anotherClient && foreignStatus.status?.sessionID == nil)
        let foreignStop = try await other.request(.init(.stop, sessionID: id))
        precondition(foreignStop.error?.code == "not_owner" && awake.isActive)
        let conflict = try await other.request(.init(.start, name: "Another build", durationMinutes: 15))
        precondition(conflict.error?.code == "busy" && awake.session?.deadline == deadline)
        awake.stop()
        precondition(automation.activeTaskName == nil)
        let lateHeartbeat = try await first.request(.init(.heartbeat, sessionID: id))
        precondition(lateHeartbeat.error?.code == "inactive" && !awake.isActive)

        await awake.start(mode: .displayMaySleep, duration: .fifteenMinutes)?.value
        let manualID = awake.sessionIdentifier
        let manualConflict = try await first.request(.init(.start, name: "Replace manual", durationMinutes: 15))
        let manualStop = try await first.request(.init(.stop, sessionID: id))
        precondition(manualConflict.error?.code == "busy" && manualStop.error?.code == "inactive")
        automation.enabled = false
        try await eventually { !automation.isListening }
        precondition(awake.isActive && awake.sessionIdentifier == manualID)
        awake.stop()
        automation.enabled = true
        try await eventually { automation.isListening }
        await first.close()
        await other.close()

        let newClient = LocalAutomationClient(endpoint: endpoint)
        let owned = try await newClient.request(.init(.start, name: "Disconnect test", durationMinutes: 15))
        precondition(owned.status?.active == true)
        await newClient.close()
        try await eventually { !awake.isActive && automation.activeTaskName == nil }

        let takeover = try await newClient.request(.init(.start, name: "User mode takeover", durationMinutes: 15))
        let takeoverID = try require(takeover.status?.sessionID)
        // The saved mode is displayOn; selecting it must still change the live
        // automation mode even though the saved preference has not changed.
        awake.displayedMode = .displayOn
        try await eventually { !awake.isChanging }
        precondition(awake.session?.mode == .displayOn && automation.activeTaskName == nil)
        let staleStop = try await newClient.request(.init(.stop, sessionID: takeoverID))
        precondition(staleStop.error?.code == "inactive" && awake.isActive)
        awake.stop()

        _ = try await newClient.request(.init(.start, name: "Protection test", durationMinutes: 15))
        // Exercise the same stop callback used by real battery/thermal policy
        // events, without draining the battery or changing notification access.
        awake.safety.onStop?(.thermalStop)
        precondition(!awake.isActive && automation.activeTaskName == nil)

        _ = try await newClient.request(.init(.start, name: "Visible automation task", durationMinutes: 15))
        try await capture(automation)
        automation.enabled = false
        precondition(!awake.isActive)
        try await eventually { !automation.isListening }
        await newClient.close()
        try FileManager.default.removeItem(atPath: endpoint.directory)
        print("PASS: app ownership, manual takeover, stale messages, disconnect, disable, protection stop, and automation UI")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }

    private static func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(predicate(), "Expected app lifecycle transition within two seconds")
    }

    private static func capture(_ automation: AutomationModel) async throws {
        let host = NSHostingView(rootView: Form { AutomationSettings() }.formStyle(.grouped)
            .environment(automation).frame(width: 680, height: 545))
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 545)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let bitmap = try require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        try require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/private/tmp/battistics-automation-\(language).png"))
        window.close()
    }
}
